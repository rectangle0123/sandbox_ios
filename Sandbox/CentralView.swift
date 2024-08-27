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
                        HStack {
                            Text(log.text)
                                .font(.subheadline)
                                .foregroundColor(log.error ? .red : log.enhanced ? .accentColor : .gray)
                        }
                    }
                    .listStyle(GroupedListStyle())
                }
                HStack {
                    Button(action: {
                        bluetoothManager.startScanning()
                    }) {
                        Text("Scan")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8.0)
                            .accentColor(.white)
                            .background(Color.accentColor)
                            .cornerRadius(4.0)
                    }
                    Button(action: {
                        bluetoothManager.readCharacteristics()
                    }) {
                        Text("Read")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8.0)
                            .accentColor(.white)
                            .background(Color.accentColor)
                            .cornerRadius(4.0)
                    }
                }
                .padding()
            }
        }
    }
}

// Bluetoothマネージャー
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Constants
    static let serviceUUID = BluetoothManager.getUUID(forKey: "BluetoothServiceUUID", fatalMessage: "BluetoothServiceUUID is missing.")
    static let serviceUUID16bit = BluetoothManager.getUUID(forKey: "BluetoothServiceUUID16bit", fatalMessage: "BluetoothServiceUUID16bit is missing.")
    static let characteristicUUID = BluetoothManager.getUUID(forKey: "BluetoothCharacteristicUUID", fatalMessage: "BluetoothCharacteristicUUID is missing.")
    
    // MARK: - Properties
    var centralManager: CBCentralManager!
    var targetPeripheral: CBPeripheral?
    var targetService: CBService?
    @Published var logs: [Log] = []
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - EventAction
    // ペリフェラルスキャン
    func startScanning() {
        log(text: "Start scaninng...", enhanced: true)
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    // キャラクタリスティックス Read
    func readCharacteristics() {
        log(text: "Start Reading...", enhanced: true)
        guard let peripheral = targetPeripheral else {
            log(text: "Error: Peripheral is not available.", error: true)
            return
        }
        guard let service = targetService else {
            log(text: "Error: Service is not available.", error: true)
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
            log(text: "Error: Bluetooth is not available.", error: true)
            return
        }
    }
    
    // ペリフェラル検知コールバック
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log(text: "Received advertise: \(peripheral.name ?? "Unknown").")
        // 指定するサービスUUIDを持つペリフェラルのみ接続する
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
              serviceUUIDs.contains(BluetoothManager.serviceUUID16bit) else {
            return
        }
        // ペリフェラルの参照を保持
        targetPeripheral = peripheral
        // ペリフェラルにデリゲートを設定する
        targetPeripheral?.delegate = self
        // スキャンを停止する
        centralManager.stopScan()
        log(text: "Stop Scanning.")
        // ペリフェラルに接続する
        centralManager.connect(peripheral, options: nil)
        log(text: "Connecting: \(peripheral.name ?? "Unknown").")
    }
    
    // ペリフェラル接続コールバック
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log(text: "Connected: \(peripheral.name ?? "Unknown").")
        // ペリフェラルのサービスを検索する
        peripheral.discoverServices([BluetoothManager.serviceUUID])
        log(text: "Discovering services.")
    }
    
    // ペリフェラル切断コールバック
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log(text: "Disconnected: \(peripheral.name ?? "Unknown") \(peripheral.identifier)")
        // ペリフェラルの参照を削除
        targetPeripheral = nil
    }
    
    // MARK: - CBPeripheralDelegate
    // サービス検知コールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else {
            log(text: "Error discovering services: \(error!.localizedDescription)", error: true)
            return
        }
        // サービスを取得する
        guard let services = peripheral.services else {
            log(text: "Error discovering services: Services not found.", error: true)
            return
        }
        guard let service = services.first(where: { $0.uuid == BluetoothManager.serviceUUID }) else {
            log(text: "Error discovering services: Target service not found.", error: true)
            return
        }
        targetService = service
        log(text: "Discovered service: \(service.uuid)")
    }
    
    // キャラクタリスティックス検出コールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else {
            log(text: "Error discovering characteristics: \(error!.localizedDescription)", error: true)
            return
        }
        log(text: "Discovering characteristics.")
        // キャラクタリスティックスからデータを取得する
        service.characteristics?.forEach { characteristic in
            log(text: "Discovered characteristic: \(characteristic.uuid)")
            if characteristic.uuid == BluetoothManager.characteristicUUID {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    // Readレスポンス受信コールバック
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log(text: "Error reading characteristic value: \(error!.localizedDescription)", error: true)
            return
        }
        // データを読み取る
        log(text: "Reading characteristics: \(characteristic.uuid)")
        if let data = characteristic.value, let text = String(data: data, encoding: .utf8) {
            log(text: text, enhanced: true)
        } else {
            log(text: "Invalid Data", error: true)
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
    private func log(text: String, error: Bool = false, enhanced: Bool = false) {
        DispatchQueue.main.async {
            self.logs.append(Log(text: text, error: error, enhanced: enhanced))
        }
    }
}

// ログ
struct Log: Identifiable {
    var id: UUID = UUID()
    var text: String
    var error: Bool
    var enhanced: Bool
}

#Preview {
    CentralView()
}
