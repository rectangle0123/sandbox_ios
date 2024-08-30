import SwiftUI
import CoreBluetooth

struct CentralView: View {
    @ObservedObject var bluetoothManager = BluetoothManager()

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            VStack {
                if bluetoothManager.logs.isEmpty {
                    Spacer()
                } else {
                    List(bluetoothManager.logs) { log in
                        VStack {
                            Text(log.text)
                                .foregroundColor(log.error ? .red : log.enhanced ? .accentColor : .gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let subText = log.subText, !subText.isEmpty {
                                Text(subText)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(/*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .listStyle(GroupedListStyle())
                }
                HStack {
                    ButtonView(
                        systemName: "s.circle",
                        action: bluetoothManager.startScanning
                    )
                    ButtonView(
                        systemName: "r.circle",
                        action: bluetoothManager.readCharacteristics
                    )
                }
                .frame(height: 50)
                .padding()
            }
        }
    }
}

struct ButtonView: View {
    @State private var isPressed = false
    var systemName: String
    var action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .frame(width: 40, height: 40)
            .foregroundColor(isPressed ? .gray : .primary)
            .padding()
            .scaleEffect(isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.65), value: isPressed)
            .onTapGesture {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    action()
                }
            }
    }
}

// Bluetoothマネージャー
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Constants
    static let serviceUUID = BluetoothManager.getUUID(
        forKey: "BluetoothServiceUUID",
        fatalMessage: "BluetoothServiceUUID is missing."
    )
    static let characteristicUUID = BluetoothManager.getUUID(
        forKey: "BluetoothCharacteristicUUID",
        fatalMessage: "BluetoothCharacteristicUUID is missing."
    )
    
    // MARK: - Properties
    var centralManager: CBCentralManager!
    var targetPeripheral: CBPeripheral?
    var targetService: CBService?
    var timeoutWorkItem: DispatchWorkItem!
    @Published var logs: [Log] = []
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - EventAction
    // ペリフェラルスキャン開始
    func startScanning() {
        log(text: "Start scaninng.", enhanced: true)
        centralManager.scanForPeripherals(
            withServices: [BluetoothManager.serviceUUID],
            options: nil
        )
        // タイムアウトの実装
        timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.log(text: "Error", subText: "Scanning has timed out.", error: true)
            self?.stopScanning()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWorkItem)
    }
    
    // ペリフェラルスキャン終了
    func stopScanning() {
        centralManager.stopScan()
        log(text: "Stop scanning.")
    }

    // キャラクタリスティックス Read
    func readCharacteristics() {
        log(text: "Start reading.", enhanced: true)
        guard let peripheral = targetPeripheral else {
            log(text: "Error", subText: "Peripheral is not available.", error: true)
            return
        }
        guard let service = targetService else {
            log(text: "Error", subText: "Service is not available.", error: true)
            return
        }
        // 接続したペリフェラルから取得したサービスのキャラクタリスティックスを検索する
        peripheral.discoverCharacteristics(nil, for: service)
        log(text: "Discovering characteristics.")
    }
    
    // MARK: - CBCentralManagerDelegate
    // Bluetooth状態検知コールバック
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            log(text: "Error", subText: "Bluetooth is not available.", error: true)
            return
        }
    }
    
    // ペリフェラル検知コールバック
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log(text: "Received advertise.", subText: "\(peripheral.name ?? "Unknown")")
        // 指定したサービスUUIDを持つペリフェラルのみ接続する
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
              serviceUUIDs.contains(BluetoothManager.serviceUUID) else {
            return
        }
        // ペリフェラルの参照を保持
        targetPeripheral = peripheral
        // ペリフェラルにデリゲートを設定する
        targetPeripheral?.delegate = self
        // スキャンを停止する
        timeoutWorkItem.cancel()
        stopScanning()
        // ペリフェラルに接続する
        centralManager.connect(peripheral, options: nil)
        log(text: "Connecting.", subText: "\(peripheral.name ?? "Unknown")")
    }
    
    // ペリフェラル接続コールバック
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log(text: "Connected.", subText:"\(peripheral.name ?? "Unknown")")
        // ペリフェラルのサービスを検索する
        peripheral.discoverServices([BluetoothManager.serviceUUID])
        log(text: "Discovering services.")
    }
    
    // ペリフェラル切断コールバック
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log(text: "Disconnected.", subText: "\(peripheral.name ?? "Unknown") \(peripheral.identifier)")
        // ペリフェラルの参照を削除
        targetPeripheral = nil
    }
    
    // MARK: - CBPeripheralDelegate
    // サービス検知コールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else {
            log(text: "Error", subText: error!.localizedDescription, error: true)
            return
        }
        // サービスを取得する
        guard let services = peripheral.services else {
            log(text: "Error",  subText: "Services not found.", error: true)
            return
        }
        guard let service = services.first(where: { $0.uuid == BluetoothManager.serviceUUID }) else {
            log(text: "Error",  subText: "Target service not found.", error: true)
            return
        }
        targetService = service
        log(text: "Discovered service.", subText: service.uuid.uuidString)
    }
    
    // キャラクタリスティックス検出コールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else {
            log(text: "Error",  subText: error!.localizedDescription, error: true)
            return
        }
        log(text: "Discovering characteristics.")
        // 指定したUUIDのキャラクタリスティックスにReadリクエストを送信する
        service.characteristics?.forEach { characteristic in
            log(text: "Discovered characteristics.", subText: characteristic.uuid.uuidString)
            if characteristic.uuid == BluetoothManager.characteristicUUID {
                peripheral.readValue(for: characteristic)
                log(text: "Sent read request.", subText: characteristic.uuid.uuidString)

            }
        }
    }
    
    // Readレスポンス受信コールバック
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log(text: "Error",  subText: error!.localizedDescription, error: true)
            return
        }
        // データを読み取る
        if let data = characteristic.value, let res = String(data: data, encoding: .utf8) {
            log(text: "Received read response.", subText: res)
        } else {
            log(text: "Received invalid Data", error: true)
        }
    }
    
    // MARK: - Private Helper
    // CBUUID生成
    private static func getUUID(forKey key: String, fatalMessage: String) -> CBUUID {
        guard let uuidString = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            fatalError(fatalMessage)
        }
        return CBUUID(string: uuidString)
    }

    // ログ出力
    private func log(text: String, subText: String? = nil, error: Bool = false, enhanced: Bool = false) {
        DispatchQueue.main.async {
            self.logs.append(Log(text: text, subText: subText, error: error, enhanced: enhanced))
        }
    }
}

// ログ
struct Log: Identifiable {
    var id: UUID = UUID()
    var text: String
    var subText: String?
    var error: Bool
    var enhanced: Bool
}

#Preview {
    CentralView()
}
