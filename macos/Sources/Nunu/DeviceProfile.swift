import Foundation

/// A real-device identity Android reports to apps. When root is on, nunu applies
/// the chosen profile with a KernelSU `resetprop` module at post-fs-data, so apps
/// (and Play Integrity) read a genuine phone's build fingerprint instead of the
/// emulator's `sdk_gphone64_arm64`. Paired with SUSFS in the kernel, this is what
/// keeps root hidden.
struct DeviceProfile: Identifiable, Equatable {
    let id: String          // stable key stored in settings
    let name: String        // shown in the picker
    let brand: String
    let manufacturer: String
    let model: String
    let device: String      // ro.product.device / ro.build.product
    let product: String     // ro.product.name
    let fingerprint: String
    let securityPatch: String

    /// Props a `resetprop` module sets. Spread across every partition's
    /// `ro.product.<partition>.*` so detectors that read a specific partition
    /// still see the spoofed value.
    var props: [String: String] {
        var p: [String: String] = [
            "ro.product.brand": brand,
            "ro.product.manufacturer": manufacturer,
            "ro.product.model": model,
            "ro.product.device": device,
            "ro.product.name": product,
            "ro.build.product": device,
            "ro.build.fingerprint": fingerprint,
            "ro.bootimage.build.fingerprint": fingerprint,
            "ro.build.version.security_patch": securityPatch,
            // Drop the tells that scream "emulator".
            "ro.build.tags": "release-keys",
            "ro.build.type": "user",
            "ro.boot.verifiedbootstate": "green",
            "ro.boot.flash.locked": "1",
            "ro.boot.vbmeta.device_state": "locked",
            "ro.debuggable": "0",
            "ro.secure": "1",
            "ro.kernel.qemu": "0",
        ]
        for partition in ["system", "system_ext", "product", "vendor", "odm"] {
            p["ro.product.\(partition).brand"] = brand
            p["ro.product.\(partition).manufacturer"] = manufacturer
            p["ro.product.\(partition).model"] = model
            p["ro.product.\(partition).device"] = device
            p["ro.product.\(partition).name"] = product
        }
        return p
    }

    /// `none` leaves Android reporting the emulator identity (root still works,
    /// just not hidden from fingerprint checks).
    static let none = DeviceProfile(
        id: "none", name: "Emulator (no spoof)",
        brand: "google", manufacturer: "Google", model: "sdk_gphone64_arm64",
        device: "emu64a", product: "sdk_gphone64_arm64",
        fingerprint: "google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.036/11228894:user/release-keys",
        securityPatch: "2023-09-05")

    static let all: [DeviceProfile] = [
        none,
        DeviceProfile(
            id: "pixel8pro", name: "Pixel 8 Pro",
            brand: "google", manufacturer: "Google", model: "Pixel 8 Pro",
            device: "husky", product: "husky",
            fingerprint: "google/husky/husky:14/AP2A.240805.005/12025142:user/release-keys",
            securityPatch: "2024-08-05"),
        DeviceProfile(
            id: "pixel6", name: "Pixel 6",
            brand: "google", manufacturer: "Google", model: "Pixel 6",
            device: "oriole", product: "oriole",
            fingerprint: "google/oriole/oriole:14/AP2A.240805.005/12025142:user/release-keys",
            securityPatch: "2024-08-05"),
        DeviceProfile(
            id: "s23ultra", name: "Samsung Galaxy S23 Ultra",
            brand: "samsung", manufacturer: "samsung", model: "SM-S918B",
            device: "dm3q", product: "dm3qxxx",
            fingerprint: "samsung/dm3qxxx/dm3q:14/UP1A.231005.007/S918BXXU4CWK9:user/release-keys",
            securityPatch: "2023-11-01"),
        DeviceProfile(
            id: "oneplus11", name: "OnePlus 11",
            brand: "OnePlus", manufacturer: "OnePlus", model: "CPH2449",
            device: "OP594DL1", product: "CPH2449",
            fingerprint: "OnePlus/CPH2449/OP594DL1:14/UKQ1.230924.001/T.R4T2.1-0:user/release-keys",
            securityPatch: "2024-05-01"),
    ]

    static func named(_ id: String) -> DeviceProfile {
        all.first { $0.id == id } ?? none
    }
}
