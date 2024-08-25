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
                        bluetoothManager.readCharacteristic()
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
    // サービスUUID
    static let serviceUUID: CBUUID = {
        guard let uuidString = Bundle.main.object(forInfoDictionaryKey: "BluetoothServiceUUID") as? String else {
            fatalError("BluetoothServiceUUID is missing in Info.plist")
        }
        return CBUUID(string: uuidString)
    }()
    // サービスUUID（16ビット）
    static let serviceUUID16bit: CBUUID = {
        guard let uuidString = Bundle.main.object(forInfoDictionaryKey: "BluetoothServiceUUID16bit") as? String else {
            fatalError("BluetoothServiceUUID16bit is missing in Info.plist")
        }
        return CBUUID(string: uuidString)
    }()
    // キャラクタリスティックUUID
    static let characteristicUUID: CBUUID = {
        guard let uuidString = Bundle.main.object(forInfoDictionaryKey: "BluetoothCharacteristicUUID") as? String else {
            fatalError("BluetoothCharacteristicUUID is missing in Info.plist")
        }
        return CBUUID(string: uuidString)
    }()

    // セントラルマネージャー
    var centralManager: CBCentralManager!
    // 接続したペリフェラル
    var targetPeripheral: CBPeripheral!
    // ログ
    @Published var logs: [Log] = []

    // 初期化
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // Bluetoothの状態が変わった場合のコールバック
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
    }

    // ペリフェラルのスキャンを開始する
    func startScanning() {
        log(text: "Start scaninng...")
        // ペリフェラルのスキャンを開始する
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    // ペリフェラルが見つかった場合のコールバック
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log(text: "Found \(peripheral.name ?? "Unknown").")
        // サービスUUIDが一致するペリフェラルのみ接続する
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(BluetoothManager.serviceUUID16bit) {
                // 重複して接続しない
                if targetPeripheral == nil || targetPeripheral.state != .connected {
                    // ペリフェラルの参照を保持
                    targetPeripheral = peripheral
                    // ペリフェラルのデリゲートを設定する
                    targetPeripheral.delegate = self
                    // スキャンを停止する
                    centralManager.stopScan()
                    log(text: "Stopped Scanning.")
                    // ペリフェラルに接続する
                    centralManager.connect(peripheral, options: nil)
                }
            }
        }
    }

    // ペリフェラルと接続した場合のコールバック
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log(text: "Connected to \(peripheral.name ?? "Unknown").")
        // ペリフェラルのサービスを検索する
        peripheral.discoverServices([BluetoothManager.serviceUUID])
    }

    // ペリフェラルのサービスが見つかった場合のコールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil else {
            log(text: "Error searching services: \(error!.localizedDescription)", error: true)
            return
        }
        // サービスが存在するか確認する
        guard let services = peripheral.services else { return }
        for service in services {
            log(text: "Found service: \(service.uuid)")
        }
    }

    // ペリフェラルが切断された場合のコールバック
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log(text: "Disconnected from \(peripheral.name ?? "Unknown") \(peripheral.identifier)")
        // ペリフェラルの参照を削除
        targetPeripheral = nil
    }

    // キャラクタリスティックリードを実行
    func readCharacteristic() {
        log(text: "Start Reading...")
        guard let services = targetPeripheral?.services else { return }
        for service in services {
            if service.uuid == BluetoothManager.serviceUUID {
                targetPeripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    // サービス内のキャラクタリスティックを検出した場合のコールバック
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else {
            log(text: "Error searching characteristics: \(error!.localizedDescription)", error: true)
            return
        }
        // キャラクタリスティックからデータを取得する
        for characteristic in service.characteristics! {
            log(text: "Found characteristics: \(characteristic.uuid)")
            if characteristic.uuid == BluetoothManager.characteristicUUID {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    // キャラクタリスティックの値が更新された場合のコールバック
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log(text: "Error reading characteristic value: \(error!.localizedDescription)", error: true)
            return
        }
        log(text: "Read characteristics: \(characteristic.uuid)")
        // データを読み取る
        if let data = characteristic.value {
            let text = String(data: data, encoding: .utf8) ?? "Invalid Data"
            log(text: text, enhanced: true)
        }
    }

    // ログ出力
    func log(text: String, error: Bool = false, enhanced: Bool = false) {
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
