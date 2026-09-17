import AppKit

/// A lightweight native interaction shield used only after the first Super Upload batch
/// has been submitted. The WebKit page stays alive underneath so ChatGPT can finish its
/// response and the native coordinator can continue the queue.
@MainActor
final class SuperUploadOverlayView: NSVisualEffectView {
    private let titleLabel = NSTextField(labelWithString: "Uploading in progress")
    private let progressLabel = NSTextField(labelWithString: "0 out of 0 files processed")
    private let progressBar = NSProgressIndicator()
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    var onCancel: (() -> Void)?

    private(set) var processedFiles = 0
    private(set) var totalFiles = 0
    var statusText: String {
        "Uploading in progress\n\(processedFiles) out of \(totalFiles) files processed"
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1

        progressLabel.font = .systemFont(ofSize: 15, weight: .medium)
        progressLabel.alignment = .center
        progressLabel.maximumNumberOfLines = 1

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.setAccessibilityLabel("Cancel Super Upload")

        let stack = NSStackView(views: [titleLabel, progressLabel, progressBar, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            progressBar.widthAnchor.constraint(equalToConstant: 320),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Super Upload interaction lock")
    }

    required init?(coder: NSCoder) { nil }

    func update(processed: Int, total: Int) {
        processedFiles = max(0, min(processed, total))
        totalFiles = max(0, total)
        progressLabel.stringValue = "\(processedFiles) out of \(totalFiles) files processed"
        progressBar.maxValue = Double(max(totalFiles, 1))
        progressBar.doubleValue = Double(processedFiles)
        setAccessibilityValue(statusText)
    }

    @objc private func cancelPressed() {
        onCancel?()
    }

    // Becoming first responder keeps typing and shortcuts away from the live WebKit page.
    // Pointer events that do not hit Cancel end here and never reach the page underneath.
    override func keyDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
