// pane_crosshair — flashes a crosshair on the cursor when focus moves to
// another tmux pane, window or session, or another NeoVim split, so the eye
// finds the cursor at once. Runs as a second pass after cursor_warp.glsl
// (see the custom-shader lines in ../config), so the warp trail lands and the
// arms shoot out of the cursor in the same frames.
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

// sRGB -> Linear conversion (same as cursor_warp.glsl)
vec3 sRGBToLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// --- CONFIGURATION ---
vec4 CROSS_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a); // same colour as the warp trail
const float DURATION = 0.45; // total animation time, seconds
const float GROW = 0.35; // fraction of DURATION the arms take to reach full length
const float HALF_WIDTH_CELLS = 16.0; // horizontal arm length, cells (16 each side + cursor = 33 columns)
const float HALF_HEIGHT_CELLS = 3.0; // vertical arm length, cells (3 each side + cursor = 7 rows)
const float BASE_THICKNESS = 0.6; // arm thickness at the cursor, fraction of the cell (height for horizontal arms, width for vertical)
const float TIP_THICKNESS = 0.15; // arm thickness at the tip, fraction of BASE_THICKNESS
const float TIP_ALPHA = 0.1; // opacity at the tips, fraction of the opacity at the cursor
const float ALPHA = 0.7; // peak opacity
const float CELL_ASPECT = 0.5; // cell width / height, to size cells from a bar or underline cursor
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

// One tapered arm along `dir` (a unit axis). `base` is how far from the centre
// the arm starts (the cell edge), `len` how far past that it reaches, `thick`
// its half-thickness at the base. Returns the arm's alpha at p.
float arm(vec2 p, vec2 center, vec2 dir, float base, float len, float thick) {
    vec2 side = vec2(-dir.y, dir.x);
    vec2 b = center + dir * base;
    vec2 t = center + dir * (base + len);
    float tipThick = thick * TIP_THICKNESS;
    float sdf = getSdfConvexQuad(p, b + side * thick, t + side * tipThick, t - side * tipThick, b - side * thick);
    // 0 at the cell edge, 1 at the tip
    float along = clamp(dot(p - b, dir) / max(len, 1e-6), 0.0, 1.0);
    return antialising(sdf, BLUR) * mix(1.0, TIP_ALPHA, along);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif

    float t = iTime - iTimeCursorChange;
    bool flagged = all(lessThan(abs(iPalette[FLAG_INDEX].rgb - FLAG), vec3(0.5 / 255.0)));
    if (!flagged || t < 0.0 || t >= DURATION) {
        return;
    }

    vec2 vu = normalize(fragCoord, 1.);
    // xy is the top-left corner (y up), zw the size
    vec4 cursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));

    // The cell, whatever the cursor shape: a block is the whole cell, a bar
    // keeps the height (NeoVim insert), an underline keeps the width (replace).
    float cellH = max(cursor.w, cursor.z / CELL_ASPECT);
    float cellW = cellH * CELL_ASPECT;
    float bottom = cursor.y - cursor.w;
    vec2 center = vec2(cursor.x + cellW * 0.5, bottom + cellH * 0.5);

    float grow = ease(clamp(t / (DURATION * GROW), 0.0, 1.0));
    float fade = 1.0 - ease(clamp(t / DURATION, 0.0, 1.0));

    float lenX = HALF_WIDTH_CELLS * cellW * grow;
    float lenY = HALF_HEIGHT_CELLS * cellH * grow;
    float thickX = cellH * 0.5 * BASE_THICKNESS;
    float thickY = cellW * 0.5 * BASE_THICKNESS;

    float shape = max(
        max(arm(vu, center, vec2(1., 0.), cellW * 0.5, lenX, thickX),
            arm(vu, center, vec2(-1., 0.), cellW * 0.5, lenX, thickX)),
        max(arm(vu, center, vec2(0., 1.), cellH * 0.5, lenY, thickY),
            arm(vu, center, vec2(0., -1.), cellH * 0.5, lenY, thickY)));

    float alpha = CROSS_COLOR.a * ALPHA * fade * shape;
    vec4 newColor = mix(fragColor, vec4(CROSS_COLOR.rgb, fragColor.a), alpha);

    // punch hole on the cursor, so it stays on top
    vec2 halfSize = cursor.zw * 0.5;
    float sdfCursor = getSdfRectangle(vu, cursor.xy + vec2(halfSize.x, -halfSize.y), halfSize);
    fragColor = mix(newColor, fragColor, step(sdfCursor, 0.));
}
