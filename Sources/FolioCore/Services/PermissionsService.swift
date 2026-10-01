import Foundation

/// What the permissions banner should say, if anything.
public struct BannerContent: Equatable, Sendable {
    public let title: String
    public let detail: String
    /// `nil` when there is no action the user can usefully take.
    public let actionLabel: String?

    public init(title: String, detail: String, actionLabel: String?) {
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }
}

/// Turns a protection state into the words shown to the user.
///
/// The copy lives here rather than in the view so it can be tested and so the
/// judgement about what the user is told sits in one place instead of being
/// spread across SwiftUI conditionals.
///
/// PDFKit preserves encryption and permission flags on save (see the
/// characterisation tests in `EngineProtectionTests`), so this copy must
/// never suggest that saving the document will change its restrictions.
/// Removing restrictions is offered only as an explicit, separate action.
public enum PermissionsService {

    public static func banner(for state: ProtectionState) -> BannerContent? {
        switch state {
        case .open:
            return nil

        case .locked:
            return BannerContent(
                title: "Este PDF pide una contraseña para abrirse",
                detail: "Sin ella no hay forma de leer el contenido. Folio no adivina contraseñas.",
                actionLabel: nil
            )

        case .restricted(let permissions):
            // Belt and braces: PDFKitEngine already reports a vacuously
            // restricted document (encrypted, nothing forbidden) as `.open`,
            // but this layer must not rely on that and re-checks here.
            guard permissions.hasRestrictions else { return nil }
            return BannerContent(
                title: "Este PDF tiene restricciones",
                detail: "El original prohíbe \(list(forbiddenActions(permissions))). "
                    + "Puedes quitarlas si tienes los derechos del documento o autorización para modificarlo.",
                actionLabel: "Quitar restricciones"
            )
        }
    }

    private static func forbiddenActions(_ permissions: Permissions) -> [String] {
        var actions: [String] = []
        if !permissions.printing { actions.append("imprimir") }
        if !permissions.copying { actions.append("copiar texto") }
        if !permissions.documentChanges { actions.append("editar") }
        if !permissions.assembly { actions.append("reorganizar páginas") }
        return actions
    }

    /// "a", "a y b", "a, b y c"
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default:
            return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
        }
    }
}
