using Toybox.Audio as Audio;
using Toybox.Application as App;
using Toybox.Lang as Lang;

// Local audio only. No network and no phone. No backlog of stale countdowns.
// Resources and lookup are generated before building by tools/build_voice_pack.py.
class ATHLTHOfflineCoach {
    var plan;
    var valid = false;
    var status = "ready";
    var current = null;
    function initialize(config) {
        plan = config;
        if (!(config instanceof Lang.Dictionary) || config["pack"] != "developer-v1" ||
            (config["language"] != "en-US" && config["language"] != "nb-NO")) { return; }
        var fields = ["restCountdown", "toRecovery", "fromRecovery"];
        for (var i = 0; i < fields.size(); i++) {
            var value = config[fields[i]];
            if (value != null && (!(value instanceof Lang.Number) || value < 1 || value > 10)) { return; }
        }
        if (!(Audio has :Output)) { return; }
        try {
            var probe = ATHLTHCoachResources.resource(config["language"], "start");
            valid = probe != null && App.loadResource(probe) != null;
        } catch (error) { valid = false; }
    }
    function poll() {
        if (!valid || current == null) { return; }
        try {
            var state = Audio.Output.getState();
            if (state == Audio.Output.PLAYBACK_ERROR) {
                status = "error"; current = null; valid = false;
            } else if (state == Audio.Output.PLAYBACK_STOPPED) {
                status = "ready"; current = null;
            }
        } catch (error) {
            status = "error"; valid = false; current = null;
        }
    }
    function speak(cue) {
        if (!valid) { return false; }
        poll();
        // Never queue a stale cue. Preserve current playback; priority and
        // interruption policies need parity testing before release.
        if (current != null) { return false; }
        try {
            var id = ATHLTHCoachResources.resource(plan["language"], cue);
            if (id == null) { status = "error"; return false; }
            var resource = App.loadResource(id);
            if (resource == null) { status = "error"; return false; }
            Audio.Output.play(resource, null);
            current = resource;
            status = "playing";
            return true;
        } catch (error) {
            status = "error"; valid = false; current = null;
            return false;
        }
    }
    function stop() {
        if (current != null) {
            try { Audio.Output.stop(); } catch (error) { status = "error"; valid = false; }
        }
        current = null;
        if (valid) { status = "ready"; }
    }
}
