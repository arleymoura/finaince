import UIKit
import UniformTypeIdentifiers

/// Share Extension principal class.
/// Shows a brief branded card while it saves the image to the App Group
/// container, then opens the main finAInce app via its custom URL scheme.
///
/// The visible UI is required: iOS does not reliably process extensionContext.open()
/// when the extension has a transparent/invisible view — it returns straight to
/// the source app.  A rendered card keeps the extension "active" long enough for
/// the open request to be dispatched.
final class ShareViewController: UIViewController {

    // MARK: - Constants

    private let appGroupID    = "group.Moura.finaince"
    private let imageFileName = "shared_image.jpg"
    private let urlScheme     = "finaince://shared-image"

    // MARK: - UI

    private let card    = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label   = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        processSharedContent()
    }

    // MARK: - UI setup

    private func buildUI() {
        // Dimmed background — signals to iOS that the extension is visually active
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        // Rounded card
        card.backgroundColor      = .systemBackground
        card.layer.cornerRadius   = 18
        card.layer.shadowColor    = UIColor.black.cgColor
        card.layer.shadowOpacity  = 0.18
        card.layer.shadowRadius   = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        // App icon (SF Symbol as stand-in; replace with UIImage(named:) if desired)
        let iconView = UIImageView(image: UIImage(systemName: "chart.pie.fill"))
        iconView.tintColor    = .systemBlue
        iconView.contentMode  = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        // Label
        label.text          = "Enviando para o Chat…"
        label.font          = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor     = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, spinner, label])
        stack.axis      = .vertical
        stack.spacing   = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 220),
            card.heightAnchor.constraint(equalToConstant: 130),

            iconView.heightAnchor.constraint(equalToConstant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 28),

            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
    }

    // MARK: - Core logic

    private func processSharedContent() {
        guard
            let item       = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachment = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            })
        else {
            openAndComplete()
            return
        }

        attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let self else { return }

            var imageData: Data?
            if let url = data as? URL {
                imageData = try? Data(contentsOf: url)
            } else if let uiImage = data as? UIImage {
                imageData = uiImage.jpegData(compressionQuality: 0.85)
            } else if let raw = data as? Data {
                imageData = raw
            }

            self.writeToAppGroup(imageData)

            DispatchQueue.main.async { self.openAndComplete() }
        }
    }

    @discardableResult
    private func writeToAppGroup(_ data: Data?) -> Bool {
        guard
            let data,
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            )
        else { return false }

        let dest = containerURL.appendingPathComponent(imageFileName)
        return (try? data.write(to: dest, options: .atomic)) != nil
    }

    /// Opens finAInce via URL scheme, then completes (dismisses) the extension.
    private func openAndComplete() {
        label.text = "Enviando a informação para o finAInce…"
        spinner.stopAnimating()

        guard let url = URL(string: urlScheme) else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        // NSExtensionContext.open() is NOT reliable in Share Extensions —
        // Apple only guarantees it in Today/Lock Screen widgets.
        // The only working approach is to access UIApplication via ObjC runtime,
        // bypassing the @available(iOSApplicationExtension, unavailable) restriction.
        openViaRuntime(url)

        // Complete after a short pause so the open request is dispatched first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Calls `UIApplication.shared.open(url)` without a direct reference to
    /// UIApplication.shared (which the compiler forbids in extensions).
    private func openViaRuntime(_ url: URL) {
        guard
            let cls    = NSClassFromString("UIApplication"),
            let result = (cls as AnyObject).perform(NSSelectorFromString("sharedApplication")),
            let app    = result.takeUnretainedValue() as? NSObject
        else { return }

        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        if app.responds(to: sel) {
            app.perform(sel, with: url, with: [:])
        }
    }
}
