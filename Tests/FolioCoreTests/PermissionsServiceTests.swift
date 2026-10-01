import Testing
import Foundation
@testable import FolioCore

@Suite("PermissionsService")
struct PermissionsServiceTests {

    private let noPrinting = Permissions(
        printing: false, copying: true, documentChanges: true, assembly: true)
    private let noPrintOrCopy = Permissions(
        printing: false, copying: false, documentChanges: true, assembly: true)

    @Test("An open document gets no banner")
    func openIsSilent() {
        #expect(PermissionsService.banner(for: .open) == nil)
    }

    @Test("A restricted document explains what is forbidden")
    func restrictedExplains() throws {
        let banner = try #require(PermissionsService.banner(for: .restricted(noPrintOrCopy)))
        #expect(banner.detail.contains("imprimir"))
        #expect(banner.detail.contains("copiar"))
        #expect(banner.actionLabel == "Quitar restricciones")
    }

    @Test("Only the actually forbidden operations are named")
    func namesOnlyWhatIsForbidden() throws {
        let banner = try #require(PermissionsService.banner(for: .restricted(noPrinting)))
        #expect(banner.detail.contains("imprimir"))
        #expect(!banner.detail.contains("copiar"))
    }

    /// The two-item and four-item joins are different code paths, and the
    /// existing tests only check that individual words appear — so a joiner
    /// that dropped the "y" and produced "imprimir, copiar texto" would pass
    /// them while shipping broken Spanish. These pin the exact sentence.
    @Test("Two forbidden operations are joined with y")
    func joinsTwoWithY() throws {
        let banner = try #require(PermissionsService.banner(for: .restricted(noPrintOrCopy)))
        #expect(banner.detail.contains("imprimir y copiar texto"))
    }

    @Test("All four forbidden operations are named and joined in Spanish")
    func joinsFourWithCommasAndY() throws {
        let nothingAllowed = Permissions(
            printing: false, copying: false, documentChanges: false, assembly: false)
        let banner = try #require(PermissionsService.banner(for: .restricted(nothingAllowed)))
        #expect(banner.detail.contains("imprimir, copiar texto, editar y reorganizar páginas"))
    }

    @Test("The banner never claims saving will change the document")
    func doesNotThreatenTheUser() throws {
        let banner = try #require(PermissionsService.banner(for: .restricted(noPrintOrCopy)))
        #expect(!banner.detail.lowercased().contains("guardar"),
                "Saving preserves restrictions, so the banner must not say otherwise")
    }

    @Test("A locked document says plainly that there is nothing to be done")
    func lockedIsHonest() throws {
        let banner = try #require(PermissionsService.banner(for: .locked))
        #expect(banner.actionLabel == nil)
        #expect(banner.title.contains("contraseña"))
    }

    @Test("A restricted document with nothing actually forbidden gets no banner")
    func vacuouslyRestricted() {
        let permissive = Permissions(
            printing: true, copying: true, documentChanges: true, assembly: true)
        #expect(PermissionsService.banner(for: .restricted(permissive)) == nil)
    }
}
