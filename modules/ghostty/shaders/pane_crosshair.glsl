// pane_crosshair — flashes a crosshair on the cursor when focus moves to
// another tmux pane, window or session, or another NeoVim split, or when the
// Ghostty window itself gets focus back, so the eye finds the cursor at once.
// Runs as a second pass after cursor_warp.glsl (see the custom-shader lines in
// ../config), so the warp trail lands and the arms shoot out of the cursor in
// the same frames.
//
// A shader keeps no state between frames and Ghostty gives it no clock of
// its own to compare against (iDate is never updated), so the trigger is
// split in two:
//   - the "focus moved" flag is palette entry 16, set to FLAG for half a
//     second by modules/tmux/scripts/Show-PaneCrosshair.sh (tmux hooks and
//     nvim-config's lua/config/pane_crosshair.lua) and then reset with OSC 104;
//   - the clock is iTimeCursorChange, i.e. the cursor jump the focus change
//     itself caused. A hook that changes nothing moves no cursor, so it starts
//     no animation.
// Entry 16 is #000000 by default; FLAG is #010203, which no one can see.
//
// Coming back to the Ghostty window from another app flashes it too, so the
// eye finds the cursor again. That one needs no flag: Ghostty clocks it itself
// in iTimeFocus, and iFocus says the window still has focus.

// sRGB -> Linear conversion (same as cursor_warp.glsl)
vec3 sRGBToLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// --- CONFIGURATION ---
vec4 CROSS_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a); // same colour as the warp trail
const float DURATION = 0.3; // total animation time, seconds
// The arms close in on the cursor: each one sweeps in from its window edge
// until it touches the cursor (the first SWEEP of DURATION, easing out like
// the warp), then is drawn into the cursor from the edge end (the rest,
// speeding up), so nothing is left when the animation ends.
const float SWEEP = 0.4;
// The arms span cursor to window edge and taper linearly with distance: full
// cursor thickness (height for horizontal arms, width for vertical) at the
// cursor, TIP_THICKNESS of it one whole window width/height away -- i.e. at
// the far tip when the cursor sits at the opposite edge. A cursor mid-window
// has two arms half that long, each ending at the thickness in between.
const float TIP_THICKNESS = 0.5;
const float TIP_ALPHA = 0.1; // opacity one window width/height away, fraction of the opacity at the cursor
const float ALPHA = 0.3; // peak opacity
const float BLUR = 1.0; // antialiasing, pixels
const vec3 FLAG = vec3(1.0, 2.0, 3.0) / 255.0; // palette 16 while the flag is up
const int FLAG_INDEX = 16;

// EaseOutCirc, the curve cursor_warp.glsl uses
float ease(float x) {
    return sqrt(1.0 - pow(x - 1.0, 2.0));
}

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Signed distance to a convex quad, from cursor_warp.glsl (Inigo Quilez's
// polygon SDF, unrolled)
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;
    return d;
}

float getSdfConvexQuad(in vec2 p, in vec2 v1, in vec2 v2, in vec2 v3, in vec2 v4) {
    float s = 1.0;
    float d = dot(p - v1, p - v1);

    d = seg(p, v1, v2, s, d);
    d = seg(p, v2, v3, s, d);
    d = seg(p, v3, v4, s, d);
    d = seg(p, v4, v1, s, d);

    return s * sqrt(d);
}

vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float antialising(float distance, float blurAmount) {
  return 1. - smoothstep(0., normalize(vec2(blurAmount, blurAmount), 0.).x, distance);
}

// One tapered arm along `dir` (a unit axis), drawn between `near` and `far`
// past the cursor's edge (`base` from the centre). It tapers over `span` to
// TIP_THICKNESS of `thick`, its half-thickness at the cursor, so its shape is
// the same whichever piece of it is showing. Returns the arm's alpha at p.
float arm(vec2 p, vec2 center, vec2 dir, float base, float near, float far, float span, float thick) {
    // Nothing showing (cursor against that edge, or the arm fully in): a
    // zero-length quad would divide by zero in seg()
    if (far - near <= 1e-5) {
        return 0.0;
    }
    vec2 side = vec2(-dir.y, dir.x);
    vec2 n = center + dir * (base + near);
    vec2 f = center + dir * (base + far);
    float nearThick = thick * mix(1.0, TIP_THICKNESS, near / span);
    float farThick = thick * mix(1.0, TIP_THICKNESS, far / span);
    float sdf = getSdfConvexQuad(p, n + side * nearThick, f + side * farThick, f - side * farThick, n - side * nearThick);
    // 0 at the cursor, 1 one span away
    float along = clamp((dot(p - center, dir) - base) / span, 0.0, 1.0);
    return antialising(sdf, BLUR) * mix(1.0, TIP_ALPHA, along);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif

    float tSwitch = iTime - iTimeCursorChange;
    float tFocus = iTime - iTimeFocus;
    bool flagged = all(lessThan(abs(iPalette[FLAG_INDEX].rgb - FLAG), vec3(0.5 / 255.0)));
    bool switched = flagged && tSwitch >= 0.0 && tSwitch < DURATION;
    bool regained = iFocus > 0 && tFocus >= 0.0 && tFocus < DURATION;
    if (!switched && !regained) {
        return;
    }
    // Both at once (a click on another pane focuses the window too): time it
    // from the later of the two
    float t = min(switched ? tSwitch : DURATION, regained ? tFocus : DURATION);

    vec2 vu = normalize(fragCoord, 1.);
    // xy is the top-left corner (y up), zw the size
    vec4 cursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec2 halfSize = cursor.zw * 0.5;
    vec2 center = cursor.xy + vec2(halfSize.x, -halfSize.y);

    // The window in the same space: x in [-edge.x, edge.x], y in [-1, 1]
    vec2 edge = vec2(iResolution.x / iResolution.y, 1.0);
    // How far an arm would run with the cursor at the opposite edge
    vec2 span = 2.0 * edge - cursor.zw;

    // Fraction of each arm still missing at its cursor end, then at its edge end
    float sweep = 1.0 - ease(clamp(t / (DURATION * SWEEP), 0.0, 1.0));
    float drawIn = 1.0 - pow(clamp((t - DURATION * SWEEP) / (DURATION * (1.0 - SWEEP)), 0.0, 1.0), 2.0);

    float right = max(edge.x - (center.x + halfSize.x), 0.0);
    float left = max((center.x - halfSize.x) + edge.x, 0.0);
    float up = max(edge.y - (center.y + halfSize.y), 0.0);
    float down = max((center.y - halfSize.y) + edge.y, 0.0);

    float shape = max(
        max(arm(vu, center, vec2(1., 0.), halfSize.x, right * sweep, right * drawIn, span.x, halfSize.y),
            arm(vu, center, vec2(-1., 0.), halfSize.x, left * sweep, left * drawIn, span.x, halfSize.y)),
        max(arm(vu, center, vec2(0., 1.), halfSize.y, up * sweep, up * drawIn, span.y, halfSize.x),
            arm(vu, center, vec2(0., -1.), halfSize.y, down * sweep, down * drawIn, span.y, halfSize.x)));

    float alpha = CROSS_COLOR.a * ALPHA * shape;
    vec4 newColor = mix(fragColor, vec4(CROSS_COLOR.rgb, fragColor.a), alpha);

    // punch hole on the cursor, so it stays on top
    float sdfCursor = getSdfRectangle(vu, center, halfSize);
    fragColor = mix(newColor, fragColor, step(sdfCursor, 0.));
}
