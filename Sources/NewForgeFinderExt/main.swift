import Foundation
import Cocoa

// Force the FinderSync class to be exported so NSExtensionMain can find it
// via objc_getClass("FinderSync").
@_cdecl("_forceExportFinderSync")
private func _forceExportFinderSync() -> AnyClass { FinderSync.self }

// Entry point: NSExtensionMain reads NSExtensionPrincipalClass from the
// bundle's Info.plist, instantiates the class, and hosts the XPC listener.
// It is exported by Foundation but not declared in public headers, so we
// declare it ourselves and call it as the process entry point.
@_silgen_name("NSExtensionMain")
private func _NSExtensionMain() -> Never

_NSExtensionMain()
