import Foundation

/// The built-in live wallpapers. Each one is a small Metal fragment shader that draws the
/// whole screen from the time and the (smoothed) mouse position. They are compiled on the
/// Mac at run time, so no build step is needed.
enum LiveStyle: String, CaseIterable, Identifiable {
    case aurora, liquid, glass, pond, halo, orbit, spectrum, flow, crystal, hex, constellation, warp, nebula, orbs, torus, iridescent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .liquid: return "Liquid Gradient"
        case .glass: return "Liquid Glass"
        case .pond: return "Ripple Pond"
        case .halo: return "Halo"
        case .orbit: return "Orbits"
        case .spectrum: return "Spectrum"
        case .flow: return "Flow Lines"
        case .crystal: return "Crystal"
        case .hex: return "Hex Grid"
        case .constellation: return "Constellation"
        case .warp: return "Warp Stars"
        case .nebula: return "Nebula"
        case .orbs: return "Glass Orbs"
        case .torus: return "Chrome Ring"
        case .iridescent: return "Iridescent"
        }
    }

    /// Shown as a small tag in the gallery.
    var kind: String {
        switch self {
        case .aurora: return "Gradient"
        case .liquid: return "Gradient"
        case .glass: return "Water"
        case .pond: return "Water"
        case .halo: return "Minimal"
        case .orbit: return "Minimal"
        case .spectrum: return "Lines"
        case .flow: return "Lines"
        case .crystal: return "Glass"
        case .hex: return "Futuristic"
        case .constellation: return "Particles"
        case .warp: return "Particles"
        case .nebula: return "Space"
        case .orbs: return "3D"
        case .torus: return "3D"
        case .iridescent: return "3D"
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
        float3 c = scene(in.uv, u.mouse, u.time, aspect, u.react, 1.0 / max(u.res.y, 1.0));
        c = hueShift(c, u.hue);
        // A touch of noise against banding on big screens.
        c += (hash(in.uv * u.res + fract(u.time)) - 0.5) / 255.0;
        return float4(clamp(c, 0.0, 1.0), 1.0);
    }
    """

    var source: String { Self.header + body + Self.footer }

    /// float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px)
    /// uv and m are 0...1 (y up); t is time in seconds (already scaled by the speed);
    /// k is how strongly it reacts to the mouse (0...1); px is one screen pixel in uv-y units,
    /// used to keep every line and edge sharp and anti-aliased at any resolution.
    var body: String {
        switch self {
        case .aurora: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
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
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
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
        case .glass: return """
        float3 glassBackdrop(float2 p, float t) {
            float g = 0.5 + 0.5 * sin(p.x * 1.3 + t * 0.20);
            float h = 0.5 + 0.5 * sin(p.y * 1.7 - t * 0.15 + p.x * 0.5);
            float3 col = mix(mix(float3(0.08, 0.30, 0.95), float3(0.70, 0.22, 0.95), g), float3(0.02, 0.78, 0.80), h * 0.55);
            return col * 0.9;
        }
        float glassH(float2 p, float2 mp, float t, float k) {
            float h = sin(dot(p, float2(1.0, 0.6)) * 6.0 + t * 1.1) * 0.010
                    + sin(dot(p, float2(-0.7, 1.0)) * 8.0 + t * 1.4) * 0.007
                    + sin(dot(p, float2(0.3, -1.0)) * 11.0 - t * 1.7) * 0.004;
            float d = length(p - mp);
            return h + k * 0.022 * sin(d * 48.0 - t * 5.0) * exp(-d * 4.5);
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float e = max(px * 1.5, 0.0008);
            float h = glassH(p, mp, t, k);
            float nx = (glassH(p + float2(e, 0.0), mp, t, k) - h) / e;
            float ny = (glassH(p + float2(0.0, e), mp, t, k) - h) / e;
            float3 n = normalize(float3(-nx, -ny, 1.0));
            float3 col = glassBackdrop(p + n.xy * 0.35, t);
            float3 L = normalize(float3(-0.45, 0.65, 1.0));
            float3 H = normalize(L + float3(0.0, 0.0, 1.0));
            col += pow(max(dot(n, H), 0.0), 600.0) * 1.4;
            col += pow(max(dot(n, normalize(float3(0.5, -0.3, 1.0))), 0.0), 900.0) * float3(0.9, 0.95, 1.0) * 0.8;
            return col;
        }
        """
        case .pond: return """
        float pondH(float2 p, float2 mp, float t, float k, float aspect) {
            float h = 0.0;
            for (int i = 0; i < 5; i++) {
                float fi = float(i);
                float period = 3.2 + fi * 0.45;
                float local = t / period + fi * 0.37;
                float cycle = floor(local);
                float age = fract(local) * period;
                float2 c = float2(hash(float2(cycle, fi * 3.1)) * aspect, 0.1 + 0.8 * hash(float2(fi * 7.7, cycle)));
                float d = length(p - c);
                float r = age * 0.16;
                h += sin((d - r) * 110.0) * exp(-abs(d - r) * 40.0) * exp(-age * 0.9) * 0.0035;
            }
            float dm = length(p - mp);
            h += k * sin(dm * 90.0 - t * 6.0) * exp(-dm * 7.0) * 0.004;
            return h;
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float e = max(px * 1.2, 0.0006);
            float h = pondH(p, mp, t, k, aspect);
            float nx = (pondH(p + float2(e, 0.0), mp, t, k, aspect) - h) / e;
            float ny = (pondH(p + float2(0.0, e), mp, t, k, aspect) - h) / e;
            float3 n = normalize(float3(-nx, -ny, 1.0));
            float3 deep = mix(float3(0.01, 0.03, 0.06), float3(0.02, 0.09, 0.14), uv.y);
            float3 sky = mix(float3(0.10, 0.25, 0.40), float3(0.55, 0.70, 0.85), clamp(0.5 + n.y * 6.0, 0.0, 1.0));
            float fres = clamp(length(n.xy) * 9.0, 0.0, 1.0);
            float3 col = mix(deep, sky * 0.55, fres);
            float3 H = normalize(normalize(float3(0.3, 0.7, 1.0)) + float3(0.0, 0.0, 1.0));
            col += pow(max(dot(n, H), 0.0), 700.0) * float3(0.85, 0.95, 1.0);
            return col;
        }
        """
        case .halo: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 home = float2(aspect * 0.5, 0.5);
            float2 c = mix(home, float2(m.x * aspect, m.y), k * 0.6);
            float d = length(p - c);
            float r = 0.26 + 0.015 * sin(t * 0.8);
            float ring = exp(-abs(d - r) * 38.0) * 0.6 + (1.0 - smoothstep(0.0015, 0.0015 + px * 1.5, abs(d - r)));
            float glow = exp(-abs(d - r) * 6.0) * 0.35;
            float a = atan2(p.y - c.y, p.x - c.x);
            float3 tint = hsv(fract(a / 6.2831853 + t * 0.03), 0.55, 1.0);
            float3 col = mix(float3(0.015, 0.015, 0.03), float3(0.05, 0.05, 0.09), uv.y);
            col += tint * (ring * 0.9 + glow);
            col += float3(0.6, 0.65, 1.0) * exp(-d * 5.0) * 0.06;
            return col;
        }
        """
        case .orbit: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            p = rot((m.x - 0.5) * 0.5 * k) * p;
            float tilt = clamp(0.32 + (m.y - 0.5) * 0.35 * k, 0.12, 0.7);
            float3 col = mix(float3(0.01, 0.01, 0.025), float3(0.03, 0.03, 0.06), uv.y);
            float2 q = float2(p.x, p.y / tilt);
            float lq = max(length(q), 0.0001);
            float grad = length(float2(q.x, q.y / tilt)) / lq;
            for (int i = 0; i < 7; i++) {
                float fi = float(i);
                float r = 0.11 + fi * 0.062;
                float3 tint = hsv(0.55 + fi * 0.045, 0.45, 1.0);
                float d = abs(lq - r) / max(grad, 0.001);
                col += tint * (1.0 - smoothstep(px * 0.5, px * 1.5, d)) * 0.35;
                float ang = t * (0.5 / (1.0 + fi * 0.6)) + fi * 1.7;
                float2 pos = float2(cos(ang) * r, sin(ang) * r * tilt);
                float dd = length(p - pos);
                float size = 0.004 + 0.0015 * fi;
                col += tint * (1.0 - smoothstep(size, size + px * 1.5, dd));
                col += tint * exp(-dd * 70.0) * 0.25;
            }
            float dc = length(p);
            col += float3(1.0, 0.9, 0.75) * (1.0 - smoothstep(0.018, 0.018 + px * 1.5, dc));
            col += float3(1.0, 0.8, 0.6) * exp(-dc * 25.0) * 0.35;
            return col;
        }
        """
        case .spectrum: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float mx = m.x * aspect;
            float3 col = mix(float3(0.01, 0.01, 0.02), float3(0.03, 0.025, 0.05), uv.y);
            float env = sin(3.1415926 * clamp(uv.x, 0.0, 1.0));
            for (int i = 0; i < 8; i++) {
                float fi = float(i);
                float amp = (0.07 + 0.04 * sin(t * 0.5 + fi * 1.3)) * (1.0 + k * 1.4 * exp(-pow((p.x - mx) * 2.5, 2.0)));
                float y = 0.5 + amp * env * sin(p.x * (2.0 + fi * 0.35) + t * (0.55 + fi * 0.08) + fi * 1.1);
                float d = abs(uv.y - y);
                float3 tint = hsv(fract(fi / 8.0 + t * 0.015), 0.65, 1.0);
                col += tint * (1.0 - smoothstep(px * 0.6, px * 1.8, d)) * 0.8;
                col += tint * exp(-d * 90.0) * 0.08;
            }
            return col;
        }
        """
        case .flow: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
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
                col += tint * (1.0 - smoothstep(px * 0.5, px * 1.6, d)) * 0.75 + tint * exp(-d * 120.0) * 0.10;
            }
            return col;
        }
        """
        case .crystal: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float scale = 4.5;
            float2 g = p * scale;
            float2 ip = floor(g);
            float2 fp = fract(g);
            float d1 = 8.0;
            float d2 = 8.0;
            float2 id1 = ip;
            for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                    float2 b = float2(float(i), float(j));
                    float2 o = float2(hash(ip + b), hash(ip + b + 17.3));
                    o = 0.5 + 0.38 * sin(t * 0.25 + 6.2831853 * o);
                    float2 r = b + o - fp;
                    float d = dot(r, r);
                    if (d < d1) { d2 = d1; d1 = d; id1 = ip + b; } else if (d < d2) { d2 = d; }
                }
            }
            float edge = sqrt(d2) - sqrt(d1);
            float pg = px * scale;
            float line = 1.0 - smoothstep(pg * 0.8, pg * 2.2, edge);
            float3 n = normalize(float3(hash(id1) - 0.5, hash(id1 + 3.3) - 0.5, 0.85));
            float2 lp = mix(float2(aspect * 0.7, 0.9), mp, k);
            float3 L = normalize(float3(lp - p, 0.6));
            float diff = max(dot(n, L), 0.0);
            float spec = pow(max(dot(reflect(-L, n), float3(0.0, 0.0, 1.0)), 0.0), 80.0);
            float3 col = mix(float3(0.03, 0.04, 0.09), float3(0.22, 0.28, 0.62), diff * diff);
            col += spec * float3(0.9, 0.95, 1.0) * 0.7;
            float3 edgeTint = hsv(fract(id1.x * 0.13 + id1.y * 0.07 + t * 0.02), 0.45, 1.0);
            col += edgeTint * line * (0.25 + 0.5 * diff);
            return col;
        }
        """
        case .hex: return """
        float hexDist(float2 p) {
            p = abs(p);
            return max(dot(p, normalize(float2(1.0, 1.7320508))), p.x);
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float scale = 16.0;
            float2 q = p * scale + float2(10.0, 10.0);
            float2 r = float2(1.0, 1.7320508);
            float2 hh = r * 0.5;
            float2 a = fmod(q, r) - hh;
            float2 b = fmod(q - hh, r) - hh;
            float2 gv = dot(a, a) < dot(b, b) ? a : b;
            float2 id = (q - gv - float2(10.0, 10.0)) / scale;
            float edge = 0.5 - hexDist(gv);
            float pg = px * scale;
            float line = 1.0 - smoothstep(pg * 0.6, pg * 1.8, edge);
            float near = k * exp(-length(id - mp) * 5.0);
            float pulse = 0.5 + 0.5 * sin(t * 1.1 - length(id - float2(aspect * 0.5, 0.5)) * 5.0);
            float3 tint = mix(float3(0.20, 0.80, 1.0), float3(0.70, 0.45, 1.0), uv.x);
            float3 col = mix(float3(0.015, 0.02, 0.04), float3(0.03, 0.035, 0.07), uv.y);
            col += tint * line * (0.10 + 0.08 * pulse + 0.85 * near);
            col += tint * near * 0.10 * smoothstep(0.0, 0.3, edge);
            return col;
        }
        """
        case .constellation: return """
        float2 starPoint(float2 cell, float t) {
            float2 o = float2(hash(cell), hash(cell + 11.7));
            return cell + 0.5 + 0.38 * sin(t * 0.35 + 6.2831853 * o);
        }
        float segDist(float2 p, float2 a, float2 b) {
            float2 pa = p - a;
            float2 ba = b - a;
            float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
            return length(pa - ba * h);
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = float2(uv.x * aspect, uv.y);
            float2 mp = float2(m.x * aspect, m.y);
            float scale = 9.0;
            float2 g = p * scale;
            float2 ip = floor(g);
            float pg = px * scale;
            float2 pts[9];
            int idx = 0;
            for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                    pts[idx] = starPoint(ip + float2(float(i), float(j)), t);
                    idx++;
                }
            }
            float near = k * exp(-length(p - mp) * 4.0);
            float3 col = mix(float3(0.01, 0.015, 0.03), float3(0.03, 0.035, 0.07), uv.y);
            float lines = 0.0;
            for (int i = 0; i < 9; i++) {
                if (i == 4) { continue; }
                float len = length(pts[4] - pts[i]);
                float a = smoothstep(1.45, 0.9, len);
                lines += (1.0 - smoothstep(pg * 0.5, pg * 1.5, segDist(g, pts[4], pts[i]))) * a;
            }
            int pairs[8] = { 1, 3, 1, 5, 7, 3, 7, 5 };
            for (int i = 0; i < 8; i += 2) {
                float2 a = pts[pairs[i]];
                float2 b = pts[pairs[i + 1]];
                float alpha = smoothstep(1.45, 0.9, length(a - b));
                lines += (1.0 - smoothstep(pg * 0.5, pg * 1.5, segDist(g, a, b))) * alpha;
            }
            float dots = 0.0;
            for (int i = 0; i < 9; i++) {
                float d = length(g - pts[i]);
                dots += 1.0 - smoothstep(0.035, 0.035 + pg * 1.5, d);
                dots += exp(-d * 18.0) * 0.25;
            }
            float3 tint = mix(float3(0.35, 0.75, 1.0), float3(0.75, 0.55, 1.0), uv.x);
            col += tint * min(lines, 1.5) * (0.16 + 0.6 * near);
            col += tint * min(dots, 1.5) * (0.6 + 0.4 * near);
            return col;
        }
        """
        case .warp: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
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
        case .nebula: return """
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
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
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float3 ro = float3(0.0, 0.0, 5.0);
            float3 rd = normalize(float3(p, -1.5));
            float yaw = (m.x - 0.5) * 1.1 * k;
            float pitch = (m.y - 0.5) * 0.7 * k;
            ro.xz = rot(yaw) * ro.xz; rd.xz = rot(yaw) * rd.xz;
            ro.yz = rot(pitch) * ro.yz; rd.yz = rot(pitch) * rd.yz;
            float3 bg = mix(float3(0.03, 0.03, 0.06), float3(0.09, 0.08, 0.16), uv.y);
            float b = dot(ro, rd);
            float c = dot(ro, ro) - 3.2 * 3.2;
            if (b * b - c < 0.0) { return bg; }
            float dist = max(0.0, -b - sqrt(b * b - c));
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
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float3 ro = float3(0.0, 0.0, 4.4);
            float3 rd = normalize(float3(p, -1.5));
            float yaw = (m.x - 0.5) * 1.4 * k;
            float pitch = (m.y - 0.5) * 0.9 * k;
            ro.xz = rot(yaw) * ro.xz; rd.xz = rot(yaw) * rd.xz;
            ro.yz = rot(pitch) * ro.yz; rd.yz = rot(pitch) * rd.yz;
            float3 bg = mix(float3(0.02, 0.02, 0.03), float3(0.09, 0.09, 0.11), uv.y);
            float b = dot(ro, rd);
            float c = dot(ro, ro) - 1.9 * 1.9;
            if (b * b - c < 0.0) { return bg + float3(0.5, 0.55, 0.7) * exp(-length(p) * 2.5) * 0.08; }
            float dist = max(0.0, -b - sqrt(b * b - c));
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
        case .iridescent: return """
        float blobSDF(float3 p, float t) {
            float3 q = p;
            q.xz = rot(t * 0.2) * q.xz;
            float d = length(q) - 1.15;
            d += 0.12 * sin(q.x * 2.6 + t * 0.7) * sin(q.y * 2.3 - t * 0.5) * sin(q.z * 2.1 + t * 0.6);
            return d * 0.8;
        }
        float3 scene(float2 uv, float2 m, float t, float aspect, float k, float px) {
            float2 p = (uv - 0.5) * float2(aspect, 1.0);
            float3 ro = float3(0.0, 0.0, 4.2);
            float3 rd = normalize(float3(p, -1.55));
            float yaw = (m.x - 0.5) * 1.3 * k;
            float pitch = (m.y - 0.5) * 0.8 * k;
            ro.xz = rot(yaw) * ro.xz; rd.xz = rot(yaw) * rd.xz;
            ro.yz = rot(pitch) * ro.yz; rd.yz = rot(pitch) * rd.yz;
            float3 bg = mix(float3(0.02, 0.02, 0.03), float3(0.08, 0.08, 0.10), uv.y);
            bg += float3(0.35, 0.3, 0.5) * exp(-length(p) * 2.2) * 0.12;
            float b = dot(ro, rd);
            float c = dot(ro, ro) - 1.6 * 1.6;
            if (b * b - c < 0.0) { return bg; }
            float dist = max(0.0, -b - sqrt(b * b - c));
            for (int i = 0; i < 64; i++) {
                float h = blobSDF(ro + rd * dist, t);
                if (h < 0.001 || dist > 8.0) { break; }
                dist += h;
            }
            if (dist > 8.0) { return bg; }
            float3 pos = ro + rd * dist;
            float2 e = float2(0.002, 0.0);
            float3 n = normalize(float3(blobSDF(pos + e.xyy, t) - blobSDF(pos - e.xyy, t),
                                        blobSDF(pos + e.yxy, t) - blobSDF(pos - e.yxy, t),
                                        blobSDF(pos + e.yyx, t) - blobSDF(pos - e.yyx, t)));
            float cosv = max(dot(n, -rd), 0.0);
            // Thin-film colours: they shift with the viewing angle, like a soap bubble or oil.
            float3 film = 0.5 + 0.5 * cos(6.2831853 * (cosv * 1.6 + float3(0.0, 0.33, 0.67) + t * 0.02));
            float3 r = reflect(rd, n);
            float env = smoothstep(-0.2, 0.8, r.y);
            float3 col = mix(float3(0.05, 0.05, 0.07), float3(0.85, 0.87, 0.95), env) * 0.55 + film * 0.55;
            col += pow(max(dot(r, normalize(float3(0.4, 0.8, 0.4))), 0.0), 80.0) * 1.2;
            col *= 0.75 + 0.25 * pow(1.0 - cosv, 2.0);
            return col;
        }
        """
        }
    }
}
