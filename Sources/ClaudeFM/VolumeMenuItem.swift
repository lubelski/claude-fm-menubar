import AppKit

/// A menu row with a speaker icon and a volume slider.
@MainActor
final class VolumeMenuItem: NSMenuItem {
    private let onChange: (Int) -> Void

    init(volume: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        super.init(title: "Volume", action: nil, keyEquivalent: "")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))

        let icon = NSImageView(frame: NSRect(x: 14, y: 6, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Volume")
        icon.contentTintColor = .secondaryLabelColor

        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100,
                              target: nil, action: nil)
        slider.frame = NSRect(x: 38, y: 4, width: 168, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))

        container.addSubview(icon)
        container.addSubview(slider)
        view = container
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onChange(Int(sender.doubleValue.rounded()))
    }
}
