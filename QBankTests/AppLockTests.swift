import Foundation
import QBankKit
import Testing
@testable import QBank

@MainActor
struct AppLockTests {
    private func lock(_ kind: DebugDeviceOwner.Kind = .faceID, defaults: UserDefaults = TestApp.freshDefaults()) -> (AppLock, DebugDeviceOwner) {
        let owner = DebugDeviceOwner(kind)
        return (AppLock(defaults: defaults, owner: owner), owner)
    }

    /// A lock turned on earlier, as a launch finds it.
    private func lockTurnedOn(_ kind: DebugDeviceOwner.Kind = .faceID) -> (AppLock, DebugDeviceOwner) {
        let defaults = TestApp.freshDefaults()
        defaults.set(true, forKey: AppLock.key)
        return lock(kind, defaults: defaults)
    }

    @Test func offByDefaultAndNeverAsks() async {
        let (lock, owner) = lock()
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        lock.enteredBackground()
        await lock.becameActive()
        #expect(!lock.isLocked)
        #expect(owner.asked == 0)
        #expect(lock.method == .faceID)
    }

    @Test func turningOnAsksFirstAndIsKeptOnTheDevice() async {
        let defaults = TestApp.freshDefaults()
        let (lock, owner) = lock(.faceIDRefusing, defaults: defaults)
        await lock.turnOn()
        #expect(!lock.isEnabled, "she cancelled Face ID, so it stays off")
        #expect(owner.asked == 1)

        owner.set(confirms: true)
        await lock.turnOn()
        #expect(lock.isEnabled)
        #expect(!lock.isLocked, "turning it on does not lock her out of the screen she is on")
        #expect(defaults.bool(forKey: AppLock.key))

        let relaunched = AppLock(defaults: defaults, owner: owner)
        #expect(relaunched.isEnabled)
        #expect(relaunched.isLocked, "a launch starts locked")
    }

    @Test func aLaunchAsksOnceAndUnlocks() async {
        let (lock, owner) = lockTurnedOn()
        #expect(lock.isLocked)
        await lock.becameActive()
        #expect(!lock.isLocked)
        #expect(owner.asked == 1)
    }

    @Test func locksInTheBackgroundAndAsksOnceOnTheWayBack() async {
        let (lock, owner) = lockTurnedOn(.faceIDRefusing)
        await lock.becameActive()
        #expect(lock.isLocked)
        #expect(owner.asked == 1)

        // Cancelling leaves the lock screen up without asking again each time the scene settles.
        await lock.becameActive()
        #expect(owner.asked == 1)

        owner.set(confirms: true)
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(owner.asked == 2)

        lock.enteredBackground()
        #expect(lock.isLocked)
        await lock.becameActive()
        #expect(!lock.isLocked)
        #expect(owner.asked == 3)
    }

    @Test func turningOffUnlocksAndStopsAsking() async {
        let (lock, owner) = lockTurnedOn(.faceIDRefusing)
        lock.turnOff()
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        lock.enteredBackground()
        await lock.becameActive()
        #expect(!lock.isLocked)
        #expect(owner.asked == 0)
    }

    @Test func aDeviceWithoutPasscodeCannotLock() async {
        let (lock, owner) = lock(.noPasscode)
        #expect(lock.method == nil)
        await lock.turnOn()
        #expect(!lock.isEnabled)
        #expect(owner.asked == 1)
    }

    /// The passcode was removed after she turned the lock on: the device is open to whoever holds
    /// it, and QBank must not keep her out of her own study.
    @Test func aDeviceThatLostItsPasscodeUnlocksForGood() async {
        let (lock, _) = lockTurnedOn(.noPasscode)
        #expect(lock.isLocked)
        await lock.becameActive()
        #expect(!lock.isLocked)
        #expect(!lock.isEnabled)
    }

    @Test func touchIDIsNamedForWhatTheDeviceHas() {
        let (lock, _) = lock(.touchID)
        #expect(lock.method == .touchID)
        #expect(UnlockMethod.touchID.name == "Touch ID")
        #expect(UnlockMethod.faceID.systemImage == "faceid")
    }

    @Test func signedOutNeverAsks() async {
        let (lock, owner) = lockTurnedOn(.faceIDRefusing)
        let (app, _) = TestApp.make(StubServer([:]), lock: lock)
        #expect(app.route == .signedOut)
        await app.becameActive()
        #expect(owner.asked == 0)
    }

    @Test func signingInWithThePasswordUnlocks() async {
        let (lock, owner) = lockTurnedOn(.faceIDRefusing)
        let (app, _) = TestApp.make(StubServer(["POST /api/sign-in/password": .ok(Bodies.signedIn())]), lock: lock)
        let signIn = SignInModel(app: app)
        signIn.email = "student@example.com"
        signIn.password = "synthetic-pass-1"
        await signIn.signIn()
        #expect(app.route == .signedIn(.student()))
        #expect(!lock.isLocked)
        await app.becameActive()
        #expect(owner.asked == 0, "the password was proof enough")
    }

    @Test func aSignedInLaunchAsks() async {
        let (lock, owner) = lockTurnedOn()
        let (app, _) = TestApp.make(StubServer([:]), account: .student(), lock: lock)
        #expect(lock.isLocked)
        await app.becameActive()
        #expect(!lock.isLocked)
        #expect(owner.asked == 1)
    }
}
