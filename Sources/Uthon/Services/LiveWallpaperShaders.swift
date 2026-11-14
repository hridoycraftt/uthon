import Foundation

/// The built-in live wallpapers. Each one is a small Metal fragment shader that draws the
/// whole screen from the time and the (smoothed) mouse position. They are compiled on the
/// Mac at run time, so no build step is needed.
enum LiveStyle: String, CaseIterable, Identifiable {
    case aurora, liquid, halo, nebula, water, silk, warp, orbs, torus, horizon, lava, bokeh, dots, contour, prism, flow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .liquid: return "Liquid Gradient"
        case .halo: return "Halo"
        case .nebula: return "Nebula"
        case .water: return "Calm Water"
        case .silk: return "Silk"
        case .warp: return "Warp Stars"
        case .orbs: return "Glass Orbs"
        case .torus: return "Chrome Ring"
        case .horizon: return "Neon Horizon"
        case .lava: return "Lava Lamp"
        case .bokeh: return "Bokeh"
        case .dots: return "Dot Matrix"
        case .contour: return "Contours"
        case .prism: return "Prism"
        case .flow: return "Flow Lines"
        }
    }

    /// 3D, gradient or particles: shown as a small tag in the gallery.
    var kind: String {
        switch self {
        case .orbs, .torus, .horizon: return "3D"
        case .warp, .bokeh, .dots, .nebula: return "Particles"
        default: return "Gradient"
        }
    }

    /// Everything shared by the styles: the full-screen triangle, noise and colour helpers.
    static let header = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float time;
        float speed;
        float2 res;
        float2 mouse;
        float hue;
        float react;
    };

    struct VOut {
        float4 pos [[position]];
        float2 uv;
    };

    vertex VOut vmain(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = p;               // (0,0) bottom-left, y up, like the mouse
        return o;
    }

    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1.0, 0.0)), u.x),
                   mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x), u.y);
    }

    float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * noise(p);
            p = p * 2.02 + float2(1.7, 9.2);
            a *= 0.5;
        }
        return v;
    }

    float3 hsv(float h, float s, float v) {
        float3 k = clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        return v * mix(float3(1.0), k, s);
    }

    float3 hueShift(float3 c, float h) {
        if (h == 0.0) { return c; }
        float3 k = float3(0.57735);
        float a = h * 6.2831853;
        float ca = cos(a);
        return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
    }

    float smin(float a, float b, float k) {
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, h) - k * h * (1.0 - h);
    }

    float2x2 rot(float a) {
        float c = cos(a);
        float s = sin(a);
        return float2x2(float2(c, s), float2(-s, c));
    }

    """

    static let footer = """

    fragment float4 fmain(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float aspect = u.res.x / max(u.res.y, 1.0);
        float3 c = scene(in.uv, u.mouse, u.time, aspect, u.react);
        c = hueShift(c, u.hue);
        // A touch of noise against banding on big screens.
        c += (hash(in.uv * u.res + fract(u.time)) - 0.5) / 255.0;
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }
    """

    var source: String { Self.header + body + Self.footer }

    /// float3 scene(float2 uv, float2 m, float t, float aspect, float k)
    /// uv and m are 0...1 (y up); t is time in seconds (already scaled by the speed);
    /// k is how strongly it reacts to the mouse (0...1).
    var body: String {
        switch self {
        case .aurora: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float3 col = mix(float3(0.01, 0.015, 0.05), float3(0.03, 0.05, 0.12), uv.y);
            for (int i = 0; i < 4; i++) {
                float fi = float(i);
                float near = exp(-pow((p.x - mp.x) * 1.4, 2.0));
                float y = 0.52 + 0.07 * fi
                    + 0.10 * sin(p.x * (1.1 + 0.3 * fi) + t * (0.25 + 0.08 * fi))
                    + 0.08 * (fbm(float2(p.x * 1.4 + t * 0.08, fi * 3.1)) - 0.5)
                    + k * 0.18 * near * (mp.y - 0.5);
                float d = abs(uv.y - y);
                float band = exp(-d * (16.0 - fi * 2.5)) * (0.55 + 0.45 * fbm(float2(p.x * 2.6 - t * 0.15, fi * 2.0)));
                float3 tint = mix(float3(0.1, 0.95, 0.65), float3(0.55, 0.35, 1.0), fi / 3.0);
                col += tint * band * (0.55 + 0.35 * k * near);
            }
            float2 g = floor(p * 140.0);
            float s = hash(g);
            col += step(0.996, s) * 0.55 * (0.5 + 0.5 * sin(t * 2.0 + s * 60.0)) * smoothstep(0.35, 1.0, uv.y);
            return col;
        }
        """
        case .liquid: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float3 cols[5] = { float3(0.98, 0.47, 0.36), float3(0.52, 0.27, 0.96), float3(0.16, 0.58, 0.96),
                               float3(0.99, 0.80, 0.40), float3(0.95, 0.36, 0.68) };
            float3 acc = float3(0.0);
            float wsum = 0.0;
            for (int i = 0; i < 5; i++) {
                float fi = float(i);
                float2 c = float2(aspect * (0.5 + 0.38 * sin(t * 0.19 + fi * 1.7)), 0.5 + 0.38 * cos(t * 0.15 + fi * 2.3));
                if (i == 0) { c = mix(c, mp, k * 0.85); }
                float d = length(p - c);
                float w = 1.0 / (pow(d, 2.2) + 0.03);
                acc += cols[i] * w;
                wsum += w;
            }
            return acc / wsum;
        }
        """
        case .halo: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 home = float2(aspect * 0.5, 0.5);
            float2 c = mix(home, float2(m.x * aspect, m.y), k * 0.6);
            float d = length(p - c);
            float r = 0.26 + 0.015 * sin(t * 0.8);
            float ring = exp(-abs(d - r) * 38.0);
            float glow = exp(-abs(d - r) * 6.0) * 0.35;
            float a = atan2(p.y - c.y, p.x - c.x);
            float3 tint = hsv(fract(a / 6.2831853 + t * 0.03), 0.55, 1.0);
            float3 col = mix(float3(0.015, 0.015, 0.03), float3(0.05, 0.05, 0.09), uv.y);
            col += tint * (ring * 0.9 + glow);
            col += float3(0.6, 0.65, 1.0) * exp(-d * 5.0) * 0.06;
            return col;
        }
        """
        case .nebula: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float2 par = (m - 0.5) * 0.12 * k;
            float n = fbm(p * 2.0 + par * 2.0 + float2(t * 0.025, -t * 0.018));
            float n2 = fbm(p * 3.6 + float2(n * 1.6, t * 0.04) + par * 3.0);
            float3 col = float3(0.015, 0.01, 0.04);
            col += float3(0.48, 0.16, 0.62) * pow(n2, 2.0) * 1.3;
            col += float3(0.10, 0.36, 0.72) * pow(n, 3.0) * 1.2;
            for (int l = 0; l < 2; l++) {
                float fl = float(l);
                float2 sp = (p + par * (1.0 + fl * 2.0)) * (90.0 + fl * 60.0);
                float2 id = floor(sp);
                float2 f = fract(sp) - 0.5;
                float h = hash(id + fl * 13.0);
                col += step(0.985, h) * smoothstep(0.09, 0.0, length(f)) * (0.6 + 0.4 * sin(t * 2.0 + h * 40.0));
            }
            float2 mp = (m - 0.5) * float2(aspect, 1.0);
            col += float3(0.6, 0.45, 1.0) * 0.10 * k * exp(-length(p - mp) * 4.0);
            return col;
        }
        """
        case .water: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float d = length(p - mp);
            // Rings spreading from the cursor bend the light patterns.
            float2 q = p * 7.0 + normalize(p - mp + 0.0001) * k * sin(d * 40.0 - t * 4.0) * exp(-d * 5.0) * 0.35;
            float c = 0.0;
            float2 w = q;
            for (int n = 0; n < 3; n++) {
                float fn = float(n) + 1.0;
                w = q + float2(sin(w.y * 0.9 / fn + t * 0.45), cos(w.x * 0.8 / fn - t * 0.4)) * 1.2;
                c += abs(sin(w.x) * sin(w.y));
            }
            c /= 3.0;
            float caustic = pow(1.0 - c, 8.0);
            float3 col = mix(float3(0.0, 0.10, 0.20), float3(0.0, 0.33, 0.42), uv.y);
            col += caustic * float3(0.45, 0.85, 0.95) * 0.75;
            col += k * 0.10 * exp(-d * 6.0) * float3(0.6, 0.9, 1.0) * (0.5 + 0.5 * sin(d * 40.0 - t * 4.0));
            return col;
        }
        """
        case .silk: return """
        float silkH(float2 p, float t) {
            return sin(p.x * 3.0 + p.y * 2.0 + t * 0.45) * 0.5
                 + sin(p.x * 5.0 - p.y * 3.0 + t * 0.6) * 0.25
                 + sin(length(p - float2(0.9, 0.5)) * 6.0 - t * 0.8) * 0.25;
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float e = 0.003;
            float h = silkH(p, t);
            float hx = silkH(p + float2(e, 0.0), t) - h;
            float hy = silkH(p + float2(0.0, e), t) - h;
            float3 n = normalize(float3(-hx, -hy, e * 4.0));
            float2 lp = mix(float2(aspect * 0.75, 0.95), float2(m.x * aspect, m.y), k);
            float3 L = normalize(float3(lp - p, 0.7));
            float diff = max(dot(n, L), 0.0);
            float spec = pow(max(dot(reflect(-L, n), float3(0.0, 0.0, 1.0)), 0.0), 36.0);
            float3 base = mix(float3(0.42, 0.25, 0.32), float3(0.80, 0.62, 0.55), uv.y);
            return base * (0.35 + 0.75 * diff) + spec * float3(1.0, 0.93, 0.88) * 0.6;
        }
        """
        case .warp: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float2 q = p - (m - 0.5) * float2(aspect, 1.0) * 0.5 * k;
            float3 col = float3(0.0, 0.0, 0.025);
            for (int l = 0; l < 5; l++) {
                float fl = float(l);
                float z = fract(fl * 0.2 + t * 0.06);
                float scale = mix(22.0, 0.7, z);
                float fade = smoothstep(0.0, 0.35, z) * smoothstep(1.0, 0.85, z);
                float2 sp = q * scale + fl * 7.3;
                float2 id = floor(sp);
                float2 f = fract(sp) - 0.5;
                float h = hash(id + fl);
                float2 off = float2(hash(id + 1.7), hash(id + 3.1)) - 0.5;
                float d = length(f - off * 0.6);
                col += step(0.55, h) * smoothstep(0.07, 0.0, d) * fade * mix(float3(0.7, 0.8, 1.0), float3(1.0, 0.82, 0.62), h);
            }
            col += float3(0.15, 0.10, 0.35) * exp(-length(q) * 3.0) * 0.45;
            return col;
        }
        """
        case .orbs: return """
        float orbsSDF(float3 p, float t) {
            float d = 1e9;
            for (int i = 0; i < 5; i++) {
                float fi = float(i);
                float3 c = float3(sin(t * 0.35 + fi * 1.3) * 1.6, cos(t * 0.29 + fi * 2.1) * 0.9, sin(t * 0.23 + fi * 0.7) * 0.8);
                d = smin(d, length(p - c) - (0.42 + 0.06 * fi), 0.55);
            }
            return d;
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float3 ro = float3(0.0, 0.0, 5.0);
            float3 rd = normalize(float3(p, -1.5));
            float yaw = (m.x - 0.5) * 1.1 * k;
            float pitch = (m.y - 0.5) * 0.7 * k;
            ro.xz = rot(yaw) * ro.xz; rd.xz = rot(yaw) * rd.xz;
            ro.yz = rot(pitch) * ro.yz; rd.yz = rot(pitch) * rd.yz;
            float3 bg = mix(float3(0.03, 0.03, 0.06), float3(0.09, 0.08, 0.16), uv.y);
            float dist = 0.0;
            for (int i = 0; i < 64; i++) {
                float h = orbsSDF(ro + rd * dist, t);
                if (h < 0.002 || dist > 12.0) { break; }
                dist += h;
            }
            if (dist > 12.0) { return bg; }
            float3 pos = ro + rd * dist;
            float2 e = float2(0.002, 0.0);
            float3 n = normalize(float3(orbsSDF(pos + e.xyy, t) - orbsSDF(pos - e.xyy, t),
                                        orbsSDF(pos + e.yxy, t) - orbsSDF(pos - e.yxy, t),
                                        orbsSDF(pos + e.yyx, t) - orbsSDF(pos - e.yyx, t)));
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            float3 L = normalize(float3(0.6, 0.8, 0.5));
            float spec = pow(max(dot(reflect(rd, n), L), 0.0), 48.0);
            float3 irid = hsv(fract(dot(n, float3(0.3, 0.5, 0.2)) + t * 0.02), 0.45, 1.0);
            float3 col = bg * 0.6 + irid * (0.15 + 0.55 * fres) + spec * 0.9;
            return col;
        }
        """
        case .torus: return """
        float ringSDF(float3 p, float t) {
            p.yz = rot(0.9 + 0.25 * sin(t * 0.3)) * p.yz;
            p.xz = rot(t * 0.35) * p.xz;
            float2 q = float2(length(p.xz) - 1.3, p.y);
            return length(q) - 0.36;
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float3 ro = float3(0.0, 0.0, 4.4);
            float3 rd = normalize(float3(p, -1.5));
            float yaw = (m.x - 0.5) * 1.4 * k;
            float pitch = (m.y - 0.5) * 0.9 * k;
            ro.xz = rot(yaw) * ro.xz; rd.xz = rot(yaw) * rd.xz;
            ro.yz = rot(pitch) * ro.yz; rd.yz = rot(pitch) * rd.yz;
            float3 bg = mix(float3(0.02, 0.02, 0.03), float3(0.09, 0.09, 0.11), uv.y);
            float dist = 0.0;
            for (int i = 0; i < 72; i++) {
                float h = ringSDF(ro + rd * dist, t);
                if (h < 0.001 || dist > 10.0) { break; }
                dist += h;
            }
            if (dist > 10.0) { return bg + float3(0.5, 0.55, 0.7) * exp(-length(p) * 2.5) * 0.08; }
            float3 pos = ro + rd * dist;
            float2 e = float2(0.002, 0.0);
            float3 n = normalize(float3(ringSDF(pos + e.xyy, t) - ringSDF(pos - e.xyy, t),
                                        ringSDF(pos + e.yxy, t) - ringSDF(pos - e.yxy, t),
                                        ringSDF(pos + e.yyx, t) - ringSDF(pos - e.yyx, t)));
            float3 r = reflect(rd, n);
            // A studio: soft top light, dark floor, a warm and a cool strip light.
            float3 env = mix(float3(0.06, 0.06, 0.08), float3(0.9, 0.92, 0.98), smoothstep(-0.1, 0.6, r.y));
            env += float3(1.0, 0.55, 0.35) * smoothstep(0.85, 1.0, r.x) * 0.6;
            env += float3(0.35, 0.6, 1.0) * smoothstep(0.85, 1.0, -r.x) * 0.5;
            float fres = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
            return env * (0.8 + 0.2 * fres);
        }
        """
        case .horizon: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - float2(0.5, 0.42)) * float2(aspect, 1.0);
            float steer = (m.x - 0.5) * 1.6 * k;
            float3 col;
            if (p.y > 0.0) {
                col = mix(float3(0.95, 0.38, 0.45), float3(0.10, 0.04, 0.25), smoothstep(0.0, 0.55, p.y));
                float2 sc = float2(-steer * 0.12, 0.17);
                float sd = length(p - sc);
                float sun = smoothstep(0.205, 0.198, sd);
                float lower = step(p.y, sc.y);
                float gap = lower * step(0.62, fract((sc.y - p.y) * 18.0 + t * 0.3));
                float3 sunCol = mix(float3(1.0, 0.86, 0.36), float3(1.0, 0.35, 0.55), clamp((sc.y + 0.2 - p.y) / 0.4, 0.0, 1.0));
                col = mix(col, sunCol, sun * (1.0 - gap));
                col += float3(1.0, 0.45, 0.55) * exp(-sd * 6.0) * 0.22;
            } else {
                float z = 0.22 / (-p.y + 0.002);
                float x = p.x * z + steer * 2.0;
                float2 g = abs(fract(float2(x, z + t * 0.9)) - 0.5);
                float w = clamp(0.035 * z, 0.03, 0.45);
                float line = max(smoothstep(0.5 - w, 0.5, g.x), smoothstep(0.5 - w, 0.5, g.y));
                float fade = exp(-z * 0.12);
                col = float3(0.05, 0.01, 0.10) + float3(0.95, 0.25, 0.85) * line * fade;
                col += float3(0.6, 0.2, 0.8) * exp(p.y * 18.0) * 0.4;
            }
            return col;
        }
        """
        case .lava: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float field = 0.0;
            for (int i = 0; i < 6; i++) {
                float fi = float(i);
                float2 c = float2(aspect * (0.15 + 0.7 * hash(float2(fi, 3.0))), 0.5 + 0.45 * sin(t * (0.12 + 0.05 * fi) + fi * 2.0));
                float r = 0.09 + 0.05 * hash(float2(fi, 7.0));
                float2 d = p - c;
                field += r * r / max(dot(d, d), 0.0001);
            }
            float2 dm = p - float2(m.x * aspect, m.y);
            field += k * 0.012 / max(dot(dm, dm), 0.0001);
            float3 bg = mix(float3(0.25, 0.05, 0.12), float3(0.05, 0.02, 0.10), uv.y);
            float inside = smoothstep(0.95, 1.05, field);
            float3 blob = mix(float3(1.0, 0.45, 0.20), float3(1.0, 0.25, 0.45), uv.y);
            float rim = smoothstep(0.6, 1.0, field) * (1.0 - inside);
            return bg + blob * inside + blob * rim * 0.35;
        }
        """
        case .bokeh: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float3 col = mix(float3(0.04, 0.03, 0.06), float3(0.10, 0.06, 0.12), uv.y);
            for (int i = 0; i < 26; i++) {
                float fi = float(i);
                float depth = 0.3 + 0.7 * hash(float2(fi, 1.0));
                float2 base = float2(hash(float2(fi, 2.0)) * aspect, fract(hash(float2(fi, 3.0)) + t * 0.02 * depth));
                float2 c = base + (m - 0.5) * 0.12 * k * depth;
                float r = 0.03 + 0.07 * depth;
                float d = length(p - c);
                float disc = smoothstep(r, r * 0.85, d);
                float edge = smoothstep(r * 0.7, r, d) * disc;
                float3 tint = mix(float3(1.0, 0.7, 0.4), float3(0.6, 0.5, 1.0), hash(float2(fi, 4.0)));
                col += tint * (disc * 0.10 + edge * 0.08) * (1.2 - depth * 0.5);
            }
            return col;
        }
        """
        case .dots: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float cells = 46.0;
            float2 p = float2(uv.x * aspect, uv.y) * cells;
            float2 id = floor(p);
            float2 f = fract(p) - 0.5;
            float2 w = (id + 0.5) / cells;
            float dm = length(w - float2(m.x * aspect, m.y));
            float wave = 0.5 + 0.5 * sin(t * 0.9 - length(w - float2(aspect * 0.5, 0.5)) * 9.0);
            float near = k * exp(-dm * 6.0);
            float r = 0.13 + 0.06 * wave + 0.22 * near;
            float dot1 = smoothstep(r, r - 0.08, length(f));
            float3 tint = mix(float3(0.35, 0.55, 1.0), float3(0.85, 0.45, 1.0), uv.x);
            float3 col = float3(0.02, 0.02, 0.035);
            col += tint * dot1 * (0.28 + 0.22 * wave + 0.8 * near);
            return col;
        }
        """
        case .contour: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float dm = length(p - float2(m.x * aspect, m.y));
            float h = fbm(p * 1.5 + float2(t * 0.025, t * 0.015)) + k * 0.3 * exp(-dm * 3.5);
            float a = abs(fract(h * 14.0) - 0.5);
            float line = smoothstep(0.40, 0.48, a);
            float3 bg = mix(float3(0.03, 0.04, 0.06), float3(0.06, 0.07, 0.10), uv.y);
            float3 tint = mix(float3(0.30, 0.85, 0.75), float3(0.55, 0.55, 1.0), smoothstep(0.3, 0.8, h));
            return bg + tint * line * 0.7 + tint * 0.08 * k * exp(-dm * 4.0);
        }
        """
        case .prism: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float2 q = p - (m - 0.5) * float2(aspect, 1.0) * k * 0.6;
            float v = sin(q.x * 2.6 + t * 0.35) + sin(q.y * 3.4 - t * 0.28) + sin((q.x + q.y) * 2.2 + t * 0.22)
                    + sin(length(q) * 4.5 - t * 0.45);
            float hue = 0.58 + 0.22 * sin(v * 0.6 + t * 0.05);
            float sheen = pow(0.5 + 0.5 * sin(v * 1.4), 3.0);
            float3 col = float3(0.03, 0.03, 0.06) + hsv(hue, 0.55, 1.0) * (0.12 + 0.75 * sheen);
            return col * (0.7 + 0.3 * smoothstep(1.3, 0.0, length(p)));
        }
        """
        case .flow: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float3 col = mix(float3(0.02, 0.03, 0.05), float3(0.04, 0.05, 0.09), uv.y);
            for (int i = 0; i < 14; i++) {
                float fi = float(i);
                float y0 = 0.08 + fi / 15.0;
                float bend = k * 0.12 * exp(-pow((p.x - mp.x) * 2.2, 2.0)) * exp(-abs(y0 - mp.y) * 5.0) * sign(y0 - mp.y + 0.0001);
                float y = y0 + 0.035 * sin(p.x * 2.2 + t * 0.4 + fi * 0.6) + bend;
                float d = abs(uv.y - y);
                float3 tint = mix(float3(0.25, 0.75, 1.0), float3(0.75, 0.45, 1.0), fi / 13.0);
                col += tint * smoothstep(0.0025, 0.0, d - 0.0008) * 0.6 + tint * exp(-d * 120.0) * 0.12;
            }
            return col;
        }
        """
        }
    }
}
