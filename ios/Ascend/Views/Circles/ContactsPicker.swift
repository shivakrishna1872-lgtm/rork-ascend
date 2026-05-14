import SwiftUI
import ContactsUI
import Contacts

/// A SwiftUI wrapper for the system contacts picker.
struct ContactsPicker: UIViewControllerRepresentable {
    var onPick: ([PickedContact]) -> Void

    struct PickedContact: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var phoneOrEmail: String
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([PickedContact]) -> Void
        init(onPick: @escaping ([PickedContact]) -> Void) { self.onPick = onPick }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let mapped: [PickedContact] = contacts.map { c in
                let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let detail = c.phoneNumbers.first?.value.stringValue
                    ?? c.emailAddresses.first?.value as? String
                    ?? ""
                return PickedContact(name: name.isEmpty ? "Friend" : name, phoneOrEmail: detail)
            }
            Task { @MainActor in self.onPick(mapped) }
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let detail = contact.phoneNumbers.first?.value.stringValue
                ?? contact.emailAddresses.first?.value as? String
                ?? ""
            let picked = PickedContact(name: name.isEmpty ? "Friend" : name, phoneOrEmail: detail)
            Task { @MainActor in self.onPick([picked]) }
        }
    }
}
