import Foundation
import IOKit.pwr_mgt

/// Holds a "prevent display sleep" power assertion while a timer is running, so a projector or
/// the Mac's own screen doesn't go dark in the middle of a talk.
final class KeepAwake {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

    var isHeld: Bool { assertionID != IOPMAssertionID(kIOPMNullAssertionID) }

    func setHeld(_ held: Bool) {
        if held { acquire() } else { release() }
    }

    private func acquire() {
        guard !isHeld else { return }
        var id = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Unreasonable Timer is running" as CFString,
            &id
        )
        if result == kIOReturnSuccess { assertionID = id }
    }

    private func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    deinit { release() }
}
