using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Activity as Activity;
using Toybox.Math as Math;

// A round-screen projection of the existing ATHLTH watch hierarchy.
// All coordinates are proportional to the inscribed circular safe area.
class ATHLTHGarminView extends Ui.View {
    var controller;
    var side = 0;
    var cx = 0;
    var cy = 0;
    const GOLD = 0xC5AA76;
    const MUTED = 0xB8B4AA;
    const TRACK = 0x39352F;
    function initialize(owner) { View.initialize(); controller = owner; }

    function text(dc, y, content, preferred, color) {
        var fraction = y / 100.0;
        var offset = (fraction - 0.5) * side;
        var radius = side * 0.45;
        var inside = radius * radius - offset * offset;
        if (inside <= 0) { return; }
        var maxWidth = 2 * Math.sqrt(inside) - side * 0.06;
        var font = preferred;
        if (dc.getTextWidthInPixels(content, font) > maxWidth) { font = Gfx.FONT_MEDIUM; }
        if (dc.getTextWidthInPixels(content, font) > maxWidth) { font = Gfx.FONT_SMALL; }
        if (dc.getTextWidthInPixels(content, font) > maxWidth) { font = Gfx.FONT_XTINY; }
        while (content.length() > 1 && dc.getTextWidthInPixels(content, font) > maxWidth) {
            content = content.substring(0, content.length() - 1);
        }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - side / 2 + side * fraction, font, content,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function clock(seconds) {
        if (seconds == null || seconds < 0) { return "--:--"; }
        var s = seconds.toNumber();
        var hours = s / 3600;
        if (hours > 0) {
            return hours.toString() + ":" + ((s / 60) % 60).format("%02d") + ":" + (s % 60).format("%02d");
        }
        return (s / 60).format("%02d") + ":" + (s % 60).format("%02d");
    }

    function distance(meters) {
        return meters == null || meters < 0 ? "-- km" : (meters / 1000.0).format("%.2f") + " km";
    }

    function pulse(bpm) {
        return bpm == null || bpm <= 0 ? "-- bpm" : bpm.format("%d") + " bpm";
    }

    function pace(speed) {
        // Garmin Activity.Info.currentSpeed is metres per second.
        if (speed == null || speed < 0.3 || speed > 20) { return "-- /km"; }
        return clock(1000.0 / speed) + " /km";
    }

    function ring(dc, fraction) {
        var radius = (side * 0.465).toNumber();
        dc.setPenWidth((side * 0.018).toNumber());
        dc.setColor(TRACK, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        if (fraction != null && fraction > 0) {
            var progress = fraction > 1 ? 1 : fraction;
            dc.setColor(GOLD, Gfx.COLOR_TRANSPARENT);
            if (progress == 1) { dc.drawCircle(cx, cy, radius); }
            else {
                dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, 90, 90 - progress * 360);
            }
        }
        dc.setPenWidth(1);
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        side = w < h ? w : h;
        cx = w / 2;
        cy = h / 2;
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var info = null;
        if (controller.session != null) { info = Activity.getActivityInfo(); }
        var elapsed = null;
        var metres = null;
        var bpm = null;
        var speed = null;
        if (info != null) {
            if (info.timerTime != null) { elapsed = info.timerTime / 1000.0; }
            metres = info.elapsedDistance;
            bpm = info.currentHeartRate;
            speed = info.currentSpeed;
        }
        var step = null;
        var progress = null;
        var fraction = null;
        if (controller.recipe != null) {
            step = controller.recipe["steps"][controller.stepIndex];
            progress = controller.stepProgress(info);
            if (controller.recipeComplete) { fraction = 1.0; }
            else if (controller.version == 3 && controller.resting) {
                var rest = controller.remainingRest(info);
                if (rest != null && step["rest"] > 0) { fraction = 1.0 - rest / step["rest"]; }
            }
            else if (controller.version == 3 && step["measure"] == "reps") {
                fraction = controller.completedSets / (controller.recipe["steps"].size() * 1.0);
            }
            else if (progress != null && step["target"] != null && step["target"] > 0) {
                fraction = progress / step["target"];
            }
        }
        ring(dc, fraction);
        text(dc, 13, controller.coach != null && controller.coach.status == "error"
            ? "COACH ERROR" : "ATHLTH", Gfx.FONT_XTINY, GOLD);

        if (controller.state == "saved") {
            text(dc, 29, "Workout saved", Gfx.FONT_MEDIUM, GOLD);
            text(dc, 45, clock(controller.savedSeconds), Gfx.FONT_NUMBER_HOT, Gfx.COLOR_WHITE);
            text(dc, 61, distance(controller.savedMeters), Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
            text(dc, 72, "Avg " + pulse(controller.savedAverageHR), Gfx.FONT_SMALL, MUTED);
            text(dc, 83, "BACK to exit", Gfx.FONT_XTINY, GOLD);
            return;
        }

        if (controller.session == null) {
            var title = controller.sport == null ? "Ready to train" : controller.sport;
            if (controller.recipe != null) { title = controller.recipe["title"]; }
            text(dc, 32, title, Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
            text(dc, 49, controller.state == "ready" ? "Ready" : controller.state, Gfx.FONT_LARGE, GOLD);
            if (controller.recipe != null && controller.state == "ready") {
                text(dc, 64, controller.recipe["steps"].size().toString() + " steps", Gfx.FONT_SMALL, MUTED);
            }
            text(dc, 78, controller.statusText, Gfx.FONT_XTINY, GOLD);
            return;
        }

        if (controller.finishArmed) {
            text(dc, 33, "Finish workout?", Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
            text(dc, 49, clock(elapsed), Gfx.FONT_NUMBER_HOT, Gfx.COLOR_WHITE);
            text(dc, 68, "START to save", Gfx.FONT_SMALL, GOLD);
            text(dc, 80, "BACK to return", Gfx.FONT_XTINY, MUTED);
            return;
        }

        var stateLabel = controller.state == "paused" ? "PAUSED" :
                         controller.state == "recording" ? "LIVE" : controller.state;
        if (controller.page == 1) {
            text(dc, 25, stateLabel + "  |  2/2", Gfx.FONT_XTINY, GOLD);
            text(dc, 40, pulse(bpm), Gfx.FONT_LARGE, Gfx.COLOR_WHITE);
            text(dc, 57, distance(metres), Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
            text(dc, 69, controller.sport == "strength" ? clock(elapsed) : pace(speed), Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
        } else if (step != null && controller.version == 3) {
            text(dc, 25, controller.resting ? "REST" : step["title"], Gfx.FONT_SMALL, GOLD);
            var main = "--";
            if (controller.recipeComplete) { main = "Done"; }
            else if (controller.resting) { main = clock(controller.remainingRest(info)); }
            else if (step["measure"] == "reps") { main = step["reps"].toString() + " reps"; }
            else if (progress != null) {
                var left = step["target"] - progress;
                main = clock(left < 0 ? 0 : left);
            }
            text(dc, 43, main, Gfx.FONT_LARGE, Gfx.COLOR_WHITE);
            text(dc, 57, controller.completedSets.toString() + "/" +
                controller.recipe["steps"].size().toString() + " sets", Gfx.FONT_SMALL, GOLD);
            if (!controller.resting && step["weight"] != null) {
                text(dc, 69, "Target " + step["weight"].format("%.1f") + " kg", Gfx.FONT_SMALL, Gfx.COLOR_WHITE);
            } else {
                text(dc, 69, pulse(bpm), Gfx.FONT_SMALL, Gfx.COLOR_WHITE);
            }
        } else if (step != null) {
            var title = step["title"];
            text(dc, 26, title, Gfx.FONT_SMALL, Gfx.COLOR_WHITE);
            var main = clock(elapsed);
            if (controller.recipeComplete) { main = "Done"; }
            else if (controller.waitingForNext) { main = "Next"; }
            else if (step["target"] != null) {
                if (progress == null) { main = step["measure"] == "time" ? "--:--" : "-- m"; }
                else {
                    var left = step["target"] - progress;
                    if (left < 0) { left = 0; }
                    main = step["measure"] == "time" ? clock(left) : left.format("%.0f") + " m";
                }
            }
            text(dc, 43, main, Gfx.FONT_LARGE, Gfx.COLOR_WHITE);
            text(dc, 57, stateLabel + "  " + (controller.stepIndex + 1).toString() + "/" +
                controller.recipe["steps"].size().toString(), Gfx.FONT_XTINY, GOLD);
            text(dc, 69, pulse(bpm) + "   " + pace(speed), Gfx.FONT_SMALL, Gfx.COLOR_WHITE);
            if (step["zone"] != null) {
                text(dc, 77, "Target Z" + step["zone"].toString(), Gfx.FONT_XTINY, MUTED);
            } else if (step["paceMin"] != null) {
                var target = "Target " + clock(step["paceMin"]);
                if (step["paceMax"] != null && step["paceMax"] != step["paceMin"]) {
                    target += "-" + clock(step["paceMax"]);
                }
                text(dc, 77, target + "/km", Gfx.FONT_XTINY, MUTED);
            }
        } else {
            text(dc, 26, stateLabel + "  |  " + controller.sport, Gfx.FONT_SMALL, GOLD);
            text(dc, 43, clock(elapsed), Gfx.FONT_NUMBER_HOT, Gfx.COLOR_WHITE);
            text(dc, 59, pulse(bpm), Gfx.FONT_MEDIUM, Gfx.COLOR_WHITE);
            if (controller.sport != "strength") {
                text(dc, 70, distance(metres) + "   " + pace(speed), Gfx.FONT_SMALL, Gfx.COLOR_WHITE);
            }
        }

        if (controller.state == "paused") {
            text(dc, 85, "START resume", Gfx.FONT_XTINY, GOLD);
        } else if (controller.version == 3 && !controller.recipeComplete && !controller.resting) {
            text(dc, 85, "DOWN confirm set", Gfx.FONT_XTINY, GOLD);
        } else if (controller.waitingForNext || (step != null && step["measure"] == "open" && !controller.recipeComplete)) {
            text(dc, 85, "DOWN next step", Gfx.FONT_XTINY, GOLD);
        } else {
            text(dc, 85, "UP page | BACK finish", Gfx.FONT_XTINY, GOLD);
        }
    }
}
