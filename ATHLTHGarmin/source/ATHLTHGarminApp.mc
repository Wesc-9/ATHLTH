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
    var version = 1;
    var recipe = null;
    var stepIndex = 0;
    var stepTime = null;
    var stepDistance = null;
    var recipeComplete = false;
    var waitingForNext = false;
    var completedSets = 0;
    var resting = false;
    var restStart = null;
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
    var page = 0;
    var savedSeconds = null;
    var savedMeters = null;
    var savedAverageHR = null;

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
        if (data["v"] != 1 && data["v"] != 2 && data["v"] != 3) { return; }
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
            var incomingRecipe = data["recipe"];
            if (data["v"] == 2 && (requestedSport == "strength" || !validRecipe(incomingRecipe))) { return; }
            if (data["v"] == 3 && (requestedSport != "strength" || !validStrength(incomingRecipe))) { return; }
            if (data["v"] == 1 && incomingRecipe != null) { return; }
            version = data["v"];
            page = 0;
            savedSeconds = null;
            savedMeters = null;
            savedAverageHR = null;
            recipe = incomingRecipe;
            stepIndex = 0;
            stepTime = null;
            stepDistance = null;
            recipeComplete = false;
            waitingForNext = false;
            completedSets = 0;
            resting = false;
            restStart = null;
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
                    setStepAnchor(Activity.getActivityInfo());
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
            var finalInfo = Activity.getActivityInfo();
            var finalSeconds = null;
            var finalMeters = null;
            var finalHR = null;
            if (finalInfo != null) {
                if (finalInfo.timerTime != null) { finalSeconds = finalInfo.timerTime / 1000.0; }
                finalMeters = finalInfo.elapsedDistance;
                finalHR = finalInfo.averageHeartRate;
            }
            if (session.save()) {
                savedSeconds = finalSeconds;
                savedMeters = finalMeters;
                savedAverageHR = finalHR;
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
        if (state == "recording" && version == 3 && recipe != null && !recipeComplete && !finishArmed) {
            var strengthInfo = Activity.getActivityInfo();
            if (strengthInfo != null) {
                if (resting) {
                    if (restStart == null && strengthInfo.timerTime != null) { restStart = strengthInfo.timerTime / 1000.0; }
                    var restLeft = remainingRest(strengthInfo);
                    if (restLeft != null && restLeft <= 0) { advanceStrength(strengthInfo); }
                } else {
                    setStepAnchor(strengthInfo);
                }
            }
        }
        if (state == "recording" && version == 2 && recipe != null && !recipeComplete && !waitingForNext && !finishArmed) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                if (stepTime == null || stepDistance == null) { setStepAnchor(info); }
                var step = recipe["steps"][stepIndex];
                var progress = stepProgress(info);
                if (progress != null && step["measure"] != "open" && progress >= step["target"]) {
                    var steps = recipe["steps"];
                    var nextNeedsConfirm = stepIndex + 1 < steps.size() &&
                        step["phase"] == "warmup" && steps[stepIndex + 1]["phase"] != "warmup" &&
                        recipe["autoStartMain"] == false;
                    if ((step["measure"] == "time" && recipe["autoAdvance"] == false) || nextNeedsConfirm) {
                        waitingForNext = true;
                        statusText = "NEXT to continue";
                        publish();
                    } else { advanceStep(info); }
                }
            }
        }
        tickCount += 1;
        if (session != null && tickCount % 5 == 0) { publish(); }
        Ui.requestUpdate();
    }
    function validRecipe(value) {
        if (!(value instanceof Lang.Dictionary) || !(value["title"] instanceof Lang.String)) { return false; }
        var steps = value["steps"];
        if (!(steps instanceof Lang.Array) || steps.size() == 0 || steps.size() > 32) { return false; }
        for (var i = 0; i < steps.size(); i++) {
            var step = steps[i];
            if (!(step instanceof Lang.Dictionary) || !(step["id"] instanceof Lang.String) ||
                step["id"].length() != 36 || !(step["title"] instanceof Lang.String)) { return false; }
            var measure = step["measure"];
            if (measure != "time" && measure != "distance" && measure != "open") { return false; }
            if (measure != "open") {
                var target = step["target"];
                if (!(target instanceof Lang.Number || target instanceof Lang.Float || target instanceof Lang.Double) ||
                    !(target > 0 && target <= 172800)) { return false; }
            }
            for (var j = 0; j < i; j++) {
                if (steps[j]["id"] == step["id"]) { return false; }
            }
        }
        return true;
    }
    function validStrength(value) {
        if (!(value instanceof Lang.Dictionary) || !(value["title"] instanceof Lang.String)) { return false; }
        var steps = value["steps"];
        if (!(steps instanceof Lang.Array) || steps.size() == 0 || steps.size() > 32) { return false; }
        for (var i = 0; i < steps.size(); i++) {
            var step = steps[i];
            if (!(step instanceof Lang.Dictionary) || !(step["id"] instanceof Lang.String) ||
                step["id"].length() != 36 || !(step["title"] instanceof Lang.String) ||
                !(step["rest"] instanceof Lang.Number) || step["rest"] < 0 || step["rest"] > 3600 ||
                !(step["setNumber"] instanceof Lang.Number) || step["setNumber"] < 1) { return false; }
            if (step["measure"] == "reps") {
                if (!(step["reps"] instanceof Lang.Number) || step["reps"] < 1 || step["reps"] > 999) { return false; }
            } else if (step["measure"] == "time") {
                if (!(step["target"] instanceof Lang.Number) || step["target"] < 1 || step["target"] > 3600) { return false; }
            } else { return false; }
            for (var j = 0; j < i; j++) {
                if (steps[j]["id"] == step["id"]) { return false; }
            }
        }
        return true;
    }

    function remainingRest(info) {
        if (!resting || restStart == null || info == null || info.timerTime == null) { return null; }
        var left = recipe["steps"][stepIndex]["rest"] - (info.timerTime / 1000.0 - restStart);
        return left < 0 ? 0 : left;
    }

    function confirmStrength(info) {
        if (resting || recipeComplete || info == null || info.timerTime == null) { return false; }
        var step = recipe["steps"][stepIndex];
        if (step["measure"] == "time") {
            var progress = stepProgress(info);
            if (progress == null || progress < step["target"]) { return false; }
        }
        completedSets += 1;
        if (completedSets == recipe["steps"].size()) {
            recipeComplete = true;
            statusText = "Plan done | BACK save";
        } else if (step["rest"] > 0) {
            resting = true;
            restStart = info.timerTime / 1000.0;
            statusText = "Rest";
        } else {
            advanceStrength(info);
            return true;
        }
        publish();
        return true;
    }

    function advanceStrength(info) {
        resting = false;
        restStart = null;
        stepIndex += 1;
        stepTime = null;
        stepDistance = null;
        setStepAnchor(info);
        statusText = "DOWN confirm set";
        publish();
    }

    function setStepAnchor(info) {
        if (info == null) { return; }
        if (stepTime == null && info.timerTime != null) { stepTime = info.timerTime / 1000.0; }
        if (stepDistance == null && info.elapsedDistance != null) { stepDistance = info.elapsedDistance; }
    }
    function stepProgress(info) {
        if (recipe == null || info == null) { return null; }
        var measure = recipe["steps"][stepIndex]["measure"];
        if (measure == "time" && stepTime != null && info.timerTime != null) {
            return info.timerTime / 1000.0 - stepTime;
        }
        if (measure == "distance" && stepDistance != null && info.elapsedDistance != null) {
            return info.elapsedDistance - stepDistance;
        }
        return null;
    }
    function nextStep() {
        if (state != "recording" || recipe == null || recipeComplete || finishArmed) { return false; }
        var info = Activity.getActivityInfo();
        if (info == null) { return false; }
        if (version == 3) { return confirmStrength(info); }
        // Manual next is for open steps and acknowledged timed targets only;
        // do not claim a distance/time target completed early.
        if (recipe["steps"][stepIndex]["measure"] != "open" && !waitingForNext) { return false; }
        advanceStep(info);
        return true;
    }
    function advanceStep(info) {
        waitingForNext = false;
        if (stepIndex + 1 >= recipe["steps"].size()) {
            recipeComplete = true;
            statusText = "Plan done | BACK save";
        } else {
            stepIndex += 1;
            stepTime = null;
            stepDistance = null;
            setStepAnchor(info);
            statusText = "START pause | NEXT step";
        }
        publish();
    }
    function sent() {
        sending = false;
        if (pending) { pending = false; publish(); }
    }
    function publish() {
        if (requestID == null) { return; }
        if (sending) { pending = true; return; }
        sequence += 1;
        var data = {"v" => version, "kind" => "event", "id" => requestID,
                    "seq" => sequence, "state" => state};
        if (recipe != null) {
            data["stepIndex"] = stepIndex;
            data["stepID"] = recipe["steps"][stepIndex]["id"];
            data["recipeComplete"] = recipeComplete;
            if (version == 3) {
                data["completedSets"] = completedSets;
                data["resting"] = resting;
            }
        }
        if (session != null && (state == "recording" || state == "paused")) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                if (info.timerTime != null) { data["seconds"] = info.timerTime / 1000.0; }
                if (info.elapsedDistance != null) { data["meters"] = info.elapsedDistance; }
                if (info.currentHeartRate != null) { data["bpm"] = info.currentHeartRate; }
            }
        }
        if (state == "saved") {
            if (savedSeconds != null) { data["seconds"] = savedSeconds; }
            if (savedMeters != null) { data["meters"] = savedMeters; }
            if (savedAverageHR != null) { data["averageBPM"] = savedAverageHR; }
        }
        sending = true;
        try {
            Comms.transmit(data, {}, new ATHLTHGarminSendListener(self));
        } catch (error) { sending = false; }
    }
}

class ATHLTHGarminDelegate extends Ui.BehaviorDelegate {
    var controller;
    function initialize(owner) { BehaviorDelegate.initialize(); controller = owner; }
    function onSelect() { controller.select(); Ui.requestUpdate(); return true; }
    function onNextPage() {
        if (!controller.nextStep() && controller.session != null && !controller.finishArmed) {
            controller.page = (controller.page + 1) % 2;
        }
        Ui.requestUpdate();
        return true;
    }
    function onPreviousPage() {
        if (controller.session != null && !controller.finishArmed) {
            controller.page = (controller.page + 1) % 2;
            Ui.requestUpdate();
            return true;
        }
        return false;
    }
    function onBack() { var handled = controller.back(); Ui.requestUpdate(); return handled; }
}
