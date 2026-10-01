import Foundation

/// Which operations a restricted PDF claims to forbid.
///
/// These flags are a convention that viewers honour by courtesy; the content
/// was always readable. See section 6 of the spec.
public struct Permissions: Sendable, Equatable {
    public var printing: Bool
    public var copying: Bool
    public var documentChanges: Bool
    public var assembly: Bool

    public init(printing: Bool, copying: Bool, documentChanges: Bool, assembly: Bool) {
        self.printing = printing
        self.copying = copying
        self.documentChanges = documentChanges
        self.assembly = assembly
    }

    /// True when at least one operation is forbidden.
    public var hasRestrictions: Bool {
        !printing || !copying || !documentChanges || !assembly
    }
}

/// How a document is protected, as classified when it is opened.
public enum ProtectionState: Sendable, Equatable {
    /// Nothing stands in the user's way: either no encryption at all, or
    /// encryption that forbids nothing. Both are reported the same because
    /// there is nothing to tell the user in either case.
    case open
    /// Opens with no password, but declares forbidden operations.
    case restricted(Permissions)
    /// Will not open without a user password.
    case locked
}
