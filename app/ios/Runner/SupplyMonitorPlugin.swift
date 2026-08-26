import Flutter
import UIKit

/// Observes mains power by watching the device's battery state.
///
/// **iOS can promise less here than Android, and this class says so.** There
/// is no background execution for this: `UIDevice` posts battery-state
/// changes only while the app is running, so coverage on iOS comes from
/// foreground sampling plus whatever background refresh the system grants.
/// It reports `periodic`, never `continuous`, and the gaps that leaves are
/// recorded as `unknown` rather than interpolated. See ADR-0006.
///
/// Overstating this would be the single most damaging thing the app could
/// do: a supply figure in a dispute pack is only worth anything if the
/// coverage behind it is real.
final class SupplyMonitorPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private static let methodChannel = "grid/supply_monitor"
    private static let eventChannel = "grid/supply_monitor/samples"

    private var sink: FlutterEventSink?
    private var observing = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SupplyMonitorPlugin()

        let methods = FlutterMethodChannel(
            name: methodChannel,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methods)

        let events = FlutterEventChannel(
            name: eventChannel,
            binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "capability":
            // Never "continuous". iOS does not offer it for this, and a
            // coverage figure built on a promise the platform never made is
            // worse than no figure at all.
            result("periodic")
        case "current":
            result(sample())
        case "start":
            startObserving()
            result(nil)
        case "stop":
            stopObserving()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        startObserving()
        // Emit at once, so a cold start has a reading rather than a gap.
        if let now = sample() { events(now) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopObserving()
        sink = nil
        return nil
    }

    // MARK: - Observation

    private func startObserving() {
        guard !observing else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        observing = true
    }

    private func stopObserving() {
        guard observing else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        UIDevice.current.isBatteryMonitoringEnabled = false
        observing = false
    }

    @objc private func batteryStateChanged() {
        guard let sink, let reading = sample() else { return }
        // Channel traffic belongs on the platform thread.
        if Thread.isMainThread {
            sink(reading)
        } else {
            DispatchQueue.main.async { sink(reading) }
        }
    }

    private func sample() -> [String: Any]? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        // `.unknown` means exactly that, and it must not be reported as "not
        // charging" — that would manufacture an outage out of a simulator or
        // a device that declines to say.
        let state = device.batteryState
        guard state != .unknown else { return nil }

        let charging = (state == .charging || state == .full)
        let level = device.batteryLevel
        let percent = level < 0 ? -1 : Int((level * 100).rounded())

        return [
            "charging": charging,
            "at": Int(Date().timeIntervalSince1970 * 1000),
            "battery": percent,
        ]
    }
}
