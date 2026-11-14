import SwiftUI

enum LibraryGlassStyle: String, CaseIterable {
    case off = "关闭"
    case clear = "清透"
    case regular = "标准"

    static let styleKey = "libraryGlassStyle"
    static let tintKey = "libraryGlassTint"
    static let defaultTint = 0.22
}

/// One shared surface under both controls leaves text and selection at full opacity.
struct LibraryGlassSurface: View {
    let style: LibraryGlassStyle
    let tint: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let strength = min(max(tint, 0), 1)
        let shape = Capsule()
        if style == .off {
            shape.fill(Color(nsColor: .controlBackgroundColor))
                .overlay { shape.strokeBorder(.quaternary) }
        } else if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
                .overlay { shape.strokeBorder(.secondary) }
        } else if #available(macOS 26.0, *) {
            let glass: Glass = style == .clear && contrast == .standard ? .clear : .regular
            shape.fill(.clear)
                .glassEffect(glass.tint(strength > 0 ? Color.accentColor.opacity(strength * 0.55) : nil), in: shape)
        } else {
            shape.fill(style == .clear ? Material.thin : Material.regular)
                .overlay { shape.fill(Color.accentColor.opacity(strength * 0.22)) }
                .overlay { shape.strokeBorder(.quaternary) }
        }
    }
}

struct LibraryGlassSettings: View {
    @AppStorage(LibraryGlassStyle.styleKey) private var style = LibraryGlassStyle.regular
    @AppStorage(LibraryGlassStyle.tintKey) private var tint = LibraryGlassStyle.defaultTint
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Section("资料库搜索与筛选栏") {
            Picker("玻璃材质", selection: $style) {
                ForEach(LibraryGlassStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Slider(value: $tint, in: 0...1, step: 0.01) { Text("着色强度") }
                Text(tint, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(width: 46, alignment: .trailing)
            }
            .disabled(style == .off || reduceTransparency)
            if reduceTransparency && style != .off {
                Text("已按系统的「降低透明度」设置使用实色背景。").font(.caption)
            }
        }
    }
}
