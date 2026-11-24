using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comms;
using Toybox.Activity as Activity;
using Toybox.ActivityRecording as Recording;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.Timer as Timer;
using Toybox.Time as Time;

class ATHLTHGarminApp extends App.AppBase {
    var controller;
    function initialize() {
        AppBase.initialize();
        controller = new ATHLTHGarminController();
    }
    function onStart(state) {
        controller.begin();
    }
    function onStop(state) {
        controller.end();
    }
    function getInitialView() {
        return [new ATHLTHGarminView(controller), new ATHLTHGarminDelegate(controller)];
    }
}

class ATHLTHGarminSendListener extends Comms.ConnectionListener {
    var controller;
    function initialize(owner) {
        ConnectionListener.initialize();
        controller = owner;
    }
    function onComplete() { controller.sent(); }
    function onError() { controller.sent(); }
}

// Recording belongs to the watch. A phone message only prepares a session;
// it never starts recording without an explicit select on the watch.
class ATHLTHGarminController {
    var requestID = null;
    var sport = null;
    var expires = 0;
    var session = null;
    var state = "idle";
    var sequence = 0;
    var finishArmed = false;
    var sending = false;
    var pending = false;
    var ticker = null;
    var tickCount = 0;
    var statusText = "Open ATHLTH on phone";

    function initialize() {}
    function begin() {
        ticker = new Timer.Timer();
        Comms.registerForPhoneAppMessages(method(:received));
        ticker.start(method(:tick), 1000, true);
    }
    function end() {
        if (ticker != null) { ticker.stop(); }
        Comms.registerForPhoneAppMessages(null);
        // Best effort to preserve a locally started recording on normal exit.
        // A crash or power failure must be reconciled, never reported as saved.
        if (session != null) {
            if (session.isRecording()) { session.stop(); }
            if (session.save()) { session = null; }
        }
    }
    function received(message) {
        var data = message.data;
        if (!(data instanceof Lang.Dictionary)) { return; }
        if (data["v"] != 1) { return; }
        var command = data["kind"];
        if (command == "prepare") {
            var id = data["id"];
            var requestedSport = data["sport"];
            var deadline = data["expires"];
            if (!(id instanceof Lang.String) || id.length() != 36 ||
                !(deadline instanceof Lang.Number) || deadline <= Time.now().value() ||
                deadline > Time.now().value() + 120) { return; }
            if (requestedSport != "running" && requestedSport != "walking" &&
                requestedSport != "strength") { return; }
            if (session != null || state == "recording" || state == "paused") { return; }
            if (id == requestID) { publish(); return; }
            if (state == "ready") { return; }
            requestID = id;
            sport = requestedSport;
            expires = deadline;
            sequence = 0;
            finishArmed = false;
            state = "ready";
            statusText = "START to confirm";
            publish();
        } else if (command == "status" && data["id"] == requestID && requestID != null) {
            publish();
        } else if (command == "cancel" && data["id"] == requestID && state == "ready") {
            state = "cancelled";
            statusText = "Cancelled";
            publish();
        }
        Ui.requestUpdate();
    }

    function select() {
        if (state == "ready") {
            if (Time.now().value() >= expires) {
                state = "expired";
                statusText = "Request expired";
                publish();
                return;
            }
            var activity = Recording.SPORT_RUNNING;
            var subSport = Recording.SUB_SPORT_GENERIC;
            if (sport == "walking") { activity = Recording.SPORT_WALKING; }
            if (sport == "strength") {
                activity = Recording.SPORT_TRAINING;
                subSport = Recording.SUB_SPORT_STRENGTH_TRAINING;
            }
            try {
                session = Recording.createSession({:name => "ATHLTH", :sport => activity, :subSport => subSport});
                if (session != null && session.start()) {
                    state = "recording";
                    statusText = "START pause | BACK save";
                } else {
                    state = "error";
                    statusText = "Recording not started";
                    if (session != null && session.discard()) { session = null; }
                }
            } catch (error) {
                state = "error";
                statusText = "Recording unavailable";
            }
            publish();
        } else if (session != null && finishArmed) {
            finishArmed = false;
            if (session.isRecording() && !session.stop()) {
                statusText = "Stop failed - retry";
                return;
            }
            if (session.save()) {
                session = null;
                state = "saved";
                statusText = "Saved on watch";
                publish();
            } else {
                state = "paused";
                statusText = "Save failed - retry";
                publish();
            }
        } else if (state == "recording" && session != null) {
            if (session.stop()) {
                state = "paused";
                statusText = "START resume | BACK save";
                publish();
            }
        } else if (state == "paused" && session != null) {
            if (session.start()) {
                state = "recording";
                statusText = "START pause | BACK save";
                publish();
            }
        }
    }

    function back() {
        if (session != null) {
            finishArmed = !finishArmed;
            if (finishArmed) { statusText = "START save | BACK return"; }
            else if (state == "recording") { statusText = "START pause | BACK save"; }
            else { statusText = "START resume | BACK save"; }
            return true;
        }
        if (state == "ready") {
            state = "cancelled";
            statusText = "Cancelled";
            publish();
            return true;
        }
        return false;
    }

    function tick() {
        if (state == "ready" && Time.now().value() >= expires) {
            state = "expired";
            statusText = "Request expired";
            publish();
        }
        tickCount += 1;
        if (session != null && tickCount % 5 == 0) { publish(); }
        Ui.requestUpdate();
    }
    function sent() {
        sending = false;
        if (pending) { pending = false; publish(); }
    }
    function publish() {
        if (requestID == null) { return; }
        if (sending) { pending = true; return; }
        sequence += 1;
        var data = {"v" => 1, "kind" => "event", "id" => requestID,
                    "seq" => sequence, "state" => state};
        if (session != null && (state == "recording" || state == "paused")) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                if (info.timerTime != null) { data["seconds"] = info.timerTime / 1000.0; }
                if (info.elapsedDistance != null) { data["meters"] = info.elapsedDistance; }
                if (info.currentHeartRate != null) { data["bpm"] = info.currentHeartRate; }
            }
        }
        sending = true;
        try {
            Comms.transmit(data, {}, new ATHLTHGarminSendListener(self));
        } catch (error) { sending = false; }
    }
}

class ATHLTHGarminView extends Ui.View {
    var controller;
    function initialize(owner) { View.initialize(); controller = owner; }
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xC5AA76, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 16 / 100, Gfx.FONT_SMALL, "ATHLTH", Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var title = "Ready";
        if (controller.sport != null) { title = controller.sport; }
        dc.drawText(w / 2, h * 29 / 100, Gfx.FONT_MEDIUM, title, Gfx.TEXT_JUSTIFY_CENTER);
        var main = controller.state;
        if (controller.session != null) {
            var info = Activity.getActivityInfo();
            if (info != null && info.timerTime != null) {
                var secs = info.timerTime / 1000;
                main = (secs / 60).format("%02d") + ":" + (secs % 60).format("%02d");
            }
        }
        dc.drawText(w / 2, h * 43 / 100, Gfx.FONT_LARGE, main, Gfx.TEXT_JUSTIFY_CENTER);
        if (controller.session != null) {
            var data = Activity.getActivityInfo();
            var hr = "-- bpm";
            if (data != null && data.currentHeartRate != null) { hr = data.currentHeartRate.toString() + " bpm"; }
            dc.drawText(w / 2, h * 64 / 100, Gfx.FONT_SMALL, hr, Gfx.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(0xC5AA76, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 78 / 100, Gfx.FONT_XTINY, controller.statusText, Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class ATHLTHGarminDelegate extends Ui.BehaviorDelegate {
    var controller;
    function initialize(owner) { BehaviorDelegate.initialize(); controller = owner; }
    function onSelect() { controller.select(); Ui.requestUpdate(); return true; }
    function onBack() { var handled = controller.back(); Ui.requestUpdate(); return handled; }
}
