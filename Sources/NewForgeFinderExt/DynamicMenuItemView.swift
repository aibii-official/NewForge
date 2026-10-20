import AppKit

/// A menu row that changes its title while Option or Control is held.
///
/// Finder Sync does not reliably call NSMenuDelegate.menuNeedsUpdate during
/// modifier tracking, so this view uses the officially supported NSMenuItem.view
/// mechanism and a timer scheduled in the event-tracking run-loop mode.
final class DynamicMenuItemView: NSView {
    private let normalTitle: String
    private let promptTitle: String
    private let plainTitle: String
    private let iconImage: NSImage?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    init(normalTitle: String,
         promptTitle: String,
         plainTitle: String,
         iconImage: NSImage?) {
        self.normalTitle = normalTitle
        self.promptTitle = promptTitle
        self.plainTitle = plainTitle
        self.iconImage = iconImage
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        guard let normalTitle = coder.decodeObject(forKey: "normalTitle") as? String,
              let promptTitle = coder.decodeObject(forKey: "promptTitle") as? String,
              let plainTitle = coder.decodeObject(forKey: "plainTitle") as? String else {
            return nil
        }
        self.normalTitle = normalTitle
        self.promptTitle = promptTitle
        self.plainTitle = plainTitle
        self.iconImage = coder.decodeObject(forKey: "iconImage") as? NSImage
        super.init(coder: coder)
        setupSubviews()
    }

    override func encode(with coder: NSCoder) {
        coder.encode(normalTitle, forKey: "normalTitle")
        coder.encode(promptTitle, forKey: "promptTitle")
        coder.encode(plainTitle, forKey: "plainTitle")
        if let iconImage {
            coder.encode(iconImage, forKey: "iconImage")
        }
        super.encode(with: coder)
    }

    private func setupSubviews() {
        wantsLayer = true
        autoresizingMask = [.width]

        iconView.image = iconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startTimer()
        } else {
            stopTimer()
        }
        updateTitle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopTimer()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var currentTitle: String {
        let flags = NSEvent.modifierFlags
        if flags.contains(.control) { return plainTitle }
        if flags.contains(.option) { return promptTitle }
        return normalTitle
    }

    private func updateTitle() {
        let title = currentTitle
        titleLabel.stringValue = title

        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        titleLabel.textColor = highlighted ? .white : .labelColor
        iconView.contentTintColor = highlighted ? .white : .labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }
}
