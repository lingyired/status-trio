import CoreAudio
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BetterDisplayVolumeUIFixRegressionTests: XCTestCase {
    func testActiveDragCannotContinueIntoNewOutputUntilFreshBegin() {
        let first = outputIdentity(id: 41, uid: "audio-a")
        let second = outputIdentity(id: 42, uid: "audio-b")
        let firstInteraction = interactionIdentity(
            output: first,
            transitionGeneration: 0
        )
        let secondInteraction = interactionIdentity(
            output: second,
            transitionGeneration: 1
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: firstInteraction,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: firstInteraction,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: secondInteraction,
            scalar: 0.5,
            canAdjust: true
        )

        interaction.setSliderValue(
            0.9,
            identity: secondInteraction,
            canAdjust: true
        )
        interaction.endEditing(identity: secondInteraction)

        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        XCTAssertEqual(emittedScalars, [0.8])
        XCTAssertEqual(finishCount, 0)

        interaction.beginEditing()
        interaction.setSliderValue(
            0.9,
            identity: secondInteraction,
            canAdjust: true
        )
        interaction.endEditing(identity: secondInteraction)

        XCTAssertEqual(emittedScalars, [0.8, 0.9])
        XCTAssertEqual(finishCount, 1)
    }

    func testMouseUpAfterInterruptedPointerDragUnlocksKeyboardWithoutFlush() {
        let first = interactionIdentity(
            output: outputIdentity(id: 40, uid: "audio-pointer-a"),
            transitionGeneration: 0
        )
        let second = interactionIdentity(
            output: outputIdentity(id: 41, uid: "audio-pointer-b"),
            transitionGeneration: 1
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: first,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: first,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: second,
            scalar: 0.4,
            canAdjust: true
        )

        // The old pointer cannot continue writing before its mouseup.
        interaction.setSliderValue(
            0.9,
            identity: second,
            canAdjust: true
        )
        XCTAssertEqual(emittedScalars, [0.8])

        // Mouseup reports the current output identity, not the old one. It
        // consumes the transition lock without flushing the discarded draft.
        interaction.endEditing(identity: second)
        XCTAssertEqual(finishCount, 0)

        // Keyboard/VoiceOver input can resume without a pointer begin.
        interaction.setSliderValue(
            0.6,
            identity: second,
            canAdjust: true
        )

        XCTAssertEqual(emittedScalars, [0.8, 0.6])
        XCTAssertEqual(finishCount, 0)
    }

    func testUnmanagedKeyboardPendingRouteChangeDoesNotLockLaterKeyboardUpdate() {
        let first = interactionIdentity(
            output: outputIdentity(id: 42, uid: "audio-keyboard-a"),
            transitionGeneration: 0
        )
        let second = interactionIdentity(
            output: outputIdentity(id: 43, uid: "audio-keyboard-b"),
            transitionGeneration: 1
        )
        var emittedScalars: [Double] = []
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: {}
        )

        interaction.receiveSystemState(
            identity: first,
            scalar: 0.2,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.6,
            identity: first,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: second,
            scalar: 0.3,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.7,
            identity: second,
            canAdjust: true
        )

        XCTAssertEqual(emittedScalars, [0.6, 0.7])
    }

    func testABATransitionAtEqualScalarRequiresFreshBeginEvenWhenBIsCoalesced() {
        let output = outputIdentity(id: 43, uid: "audio-display")
        let before = interactionIdentity(
            output: output,
            transitionGeneration: 0
        )
        // A -> B -> A may publish only the final A state. Its monotonic epoch
        // must still make the interaction identity observably different.
        let after = interactionIdentity(
            output: output,
            transitionGeneration: 2
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: before,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: before,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: after,
            scalar: 0.5,
            canAdjust: true
        )

        interaction.setSliderValue(
            0.9,
            identity: after,
            canAdjust: true
        )
        interaction.endEditing(identity: after)

        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        XCTAssertEqual(emittedScalars, [0.8])
        XCTAssertEqual(finishCount, 0)

        interaction.beginEditing()
        interaction.setSliderValue(
            0.9,
            identity: after,
            canAdjust: true
        )
        interaction.endEditing(identity: after)

        XCTAssertEqual(emittedScalars, [0.8, 0.9])
        XCTAssertEqual(finishCount, 1)
    }

    func testCapabilityLossAndRecoveryMidDragRequiresFreshBegin() {
        let identity = interactionIdentity(
            output: outputIdentity(id: 44, uid: "audio-capability"),
            transitionGeneration: 0
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.8,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: false
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.5,
            canAdjust: true
        )

        interaction.setSliderValue(
            0.7,
            identity: identity,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(interaction.value, 0.5, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        XCTAssertEqual(emittedScalars, [0.8])
        XCTAssertEqual(finishCount, 0)

        interaction.beginEditing()
        interaction.setSliderValue(
            0.7,
            identity: identity,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(emittedScalars, [0.8, 0.7])
        XCTAssertEqual(finishCount, 1)
    }

    func testScalarUnavailableRecoveryMidDragRequiresFreshBegin() {
        let identity = interactionIdentity(
            output: outputIdentity(id: 45, uid: "audio-scalar"),
            transitionGeneration: 0
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.4,
            canAdjust: true
        )
        interaction.beginEditing()
        interaction.setSliderValue(
            0.7,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: nil,
            canAdjust: false
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.4,
            canAdjust: true
        )

        interaction.setSliderValue(
            0.6,
            identity: identity,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(emittedScalars, [0.7])
        XCTAssertEqual(finishCount, 0)

        interaction.beginEditing()
        interaction.setSliderValue(
            0.6,
            identity: identity,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(emittedScalars, [0.7, 0.6])
        XCTAssertEqual(finishCount, 1)
    }

    func testPassiveRouteTransitionKeepsKeyboardBindingUsableWithoutBegin() {
        let first = interactionIdentity(
            output: outputIdentity(id: 46, uid: "audio-keyboard-a"),
            transitionGeneration: 0
        )
        let second = interactionIdentity(
            output: outputIdentity(id: 47, uid: "audio-keyboard-b"),
            transitionGeneration: 1
        )
        var emittedScalars: [Double] = []
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: {}
        )

        interaction.receiveSystemState(
            identity: first,
            scalar: 0.3,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: second,
            scalar: 0.3,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.6,
            identity: second,
            canAdjust: true
        )

        XCTAssertEqual(emittedScalars, [0.6])
        XCTAssertFalse(interaction.isEditing)
    }

    func testUnmanagedBindingUpdateDoesNotBlockLaterSystemSynchronization() {
        let identity = interactionIdentity(
            output: outputIdentity(id: 48, uid: "audio-unmanaged"),
            transitionGeneration: 0
        )
        var emittedScalars: [Double] = []
        var finishCount = 0
        var interaction = VolumeControlInteraction(
            setVolume: { emittedScalars.append($0) },
            finishVolume: { finishCount += 1 }
        )

        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.2,
            canAdjust: true
        )
        interaction.setSliderValue(
            0.6,
            identity: identity,
            canAdjust: true
        )
        interaction.receiveSystemState(
            identity: identity,
            scalar: 0.35,
            canAdjust: true
        )
        interaction.endEditing(identity: identity)

        XCTAssertEqual(interaction.value, 0.35, accuracy: 0.000_001)
        XCTAssertFalse(interaction.isEditing)
        XCTAssertEqual(emittedScalars, [0.6])
        XCTAssertEqual(finishCount, 0)
    }

    func testMapperCarriesExternalVolumeTransitionGeneration() {
        let output = AudioOutputDevice(
            id: 49,
            name: "External display",
            uid: "audio-display",
            isCurrent: true
        )
        let state = AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.5,
                isMuted: false,
                deviceName: output.name,
                currentDevice: output,
                outputDevices: [output],
                canSetVolume: true,
                canMute: true,
                muteState: .unmuted,
                externalVolumeTransitionGeneration: 17
            ),
            controllerAvailable: true,
            localization: makeEnglishLocalization()
        )

        XCTAssertEqual(state.interactionIdentity.transitionGeneration, 17)
    }

    func testMonitorAdvancesExternalVolumeGenerationAcrossNativeABASameScalar() async {
        let first = AudioOutputDevice(
            id: 51,
            name: "First output",
            uid: "audio-first",
            isCurrent: true
        )
        let second = AudioOutputDevice(
            id: 52,
            name: "Second output",
            uid: "audio-second",
            isCurrent: true
        )
        let sequence = RouteReadingSequence([
            routeReading(device: first, scalar: 0.5),
            routeReading(device: second, scalar: 0.5),
            routeReading(device: first, scalar: 0.5)
        ])
        let monitor = VolumeMonitor(
            statusReader: CoreAudioStatusReader { _ in
                AudioStatusReading(volume: sequence.next(), outputDevices: nil)
            },
            eventMonitor: PassiveVolumeEventMonitor()
        )
        var iterator = monitor.updates.makeAsyncIterator()
        var statuses: [VolumeStatus] = []

        for _ in 0..<3 {
            monitor.refresh()
            guard let status = await iterator.next() else {
                XCTFail("VolumeMonitor finished before publishing all route states")
                monitor.stop()
                return
            }
            statuses.append(status)
        }
        monitor.stop()

        XCTAssertEqual(statuses.map { $0.currentDevice?.id }, [51, 52, 51])
        XCTAssertEqual(statuses.map(\.scalar), [0.5, 0.5, 0.5])
        XCTAssertLessThan(
            statuses[0].externalVolumeTransitionGeneration,
            statuses[1].externalVolumeTransitionGeneration
        )
        XCTAssertLessThan(
            statuses[1].externalVolumeTransitionGeneration,
            statuses[2].externalVolumeTransitionGeneration
        )
    }

    func testFallbackOnlyDescriptionsAndActionableNotConfirmedCopyInEveryLocale() throws {
        let expected: [AppLanguage: LocalizedFallbackCopy] = [
            .english: LocalizedFallbackCopy(
                controlMethodDescription: "If the status panel cannot control this device’s volume, choose BetterDisplay.",
                displayDescription: "Choose the display that corresponds to this audio output.",
                footnote: "Native macOS volume control takes priority. The selected method is used when native control is unavailable.",
                requirements: "If the connection fails, enable CLI access and notification-based integration in BetterDisplay settings.",
                notConfirmed: "The volume change could not be confirmed. Select “Detect Again” and try again."
            ),
            .simplifiedChinese: LocalizedFallbackCopy(
                controlMethodDescription: "如果状态面板的音量控制无法调节此设备，可改用 BetterDisplay。",
                displayDescription: "选择与此音频输出对应的显示器。",
                footnote: "macOS 原生音量控制优先；原生控制不可用时才使用所选方式。",
                requirements: "如果连接失败，请在 BetterDisplay 设置中启用 CLI 访问和基于通知的集成。",
                notConfirmed: "无法确认音量更改。请点按“重新检测”后重试。"
            ),
            .traditionalChinese: LocalizedFallbackCopy(
                controlMethodDescription: "如果狀態面板的音量控制無法調整此裝置，可改用 BetterDisplay。",
                displayDescription: "選擇與此音訊輸出對應的顯示器。",
                footnote: "macOS 原生音量控制優先；無法使用原生控制時，才會使用所選方式。",
                requirements: "若連線失敗，請在 BetterDisplay 設定中啟用 CLI 存取和通知式整合。",
                notConfirmed: "無法確認音量變更。請按一下「重新偵測」後再試一次。"
            ),
            .japanese: LocalizedFallbackCopy(
                controlMethodDescription: "ステータスパネルの音量コントロールでこのデバイスを調整できない場合は、BetterDisplay を使用してください。",
                displayDescription: "このオーディオ出力に対応するディスプレイを選択します。",
                footnote: "macOS のネイティブ音量制御が優先されます。ネイティブ制御を利用できない場合に、選択した方法を使用します。",
                requirements: "接続に失敗する場合は、BetterDisplay の設定で CLI アクセスと通知ベースの連携を有効にしてください。",
                notConfirmed: "音量の変更を確認できませんでした。「再検出」を選択して、もう一度お試しください。"
            ),
            .korean: LocalizedFallbackCopy(
                controlMethodDescription: "상태 패널의 볼륨 제어로 이 기기를 조절할 수 없다면 BetterDisplay를 사용하십시오.",
                displayDescription: "이 오디오 출력에 해당하는 디스플레이를 선택하십시오.",
                footnote: "macOS 기본 볼륨 제어가 우선합니다. 기본 제어를 사용할 수 없을 때 선택한 방식을 사용합니다.",
                requirements: "연결에 실패하면 BetterDisplay 설정에서 CLI 접근 및 알림 기반 통합을 활성화하십시오.",
                notConfirmed: "볼륨 변경을 확인할 수 없습니다. ‘다시 감지’를 선택한 후 다시 시도하십시오."
            ),
            .spanish: LocalizedFallbackCopy(
                controlMethodDescription: "Si los controles de volumen del panel de estado no pueden controlar este dispositivo, usa BetterDisplay.",
                displayDescription: "Elige la pantalla que corresponde a esta salida de audio.",
                footnote: "El control de volumen nativo de macOS tiene prioridad. El método seleccionado se usa cuando el control nativo no está disponible.",
                requirements: "Si la conexión falla, activa el acceso a la CLI y la integración basada en notificaciones en los ajustes de BetterDisplay.",
                notConfirmed: "No se pudo confirmar el cambio de volumen. Selecciona «Volver a detectar» e inténtalo de nuevo."
            ),
            .french: LocalizedFallbackCopy(
                controlMethodDescription: "Si les commandes de volume du panneau d’état ne contrôlent pas cet appareil, utilisez BetterDisplay.",
                displayDescription: "Choisissez l’écran correspondant à cette sortie audio.",
                footnote: "Le contrôle de volume natif de macOS est prioritaire. La méthode sélectionnée est utilisée lorsque le contrôle natif n’est pas disponible.",
                requirements: "Si la connexion échoue, activez l’accès à la CLI et l’intégration par notifications dans les réglages de BetterDisplay.",
                notConfirmed: "Le changement de volume n’a pas pu être confirmé. Sélectionnez « Détecter à nouveau », puis réessayez."
            ),
            .german: LocalizedFallbackCopy(
                controlMethodDescription: "Wenn die Lautstärkeregelung im Statusfenster dieses Gerät nicht steuern kann, verwende BetterDisplay.",
                displayDescription: "Wähle das Display, das diesem Audioausgang entspricht.",
                footnote: "Die native macOS-Lautstärkesteuerung hat Vorrang. Die ausgewählte Methode wird verwendet, wenn die native Steuerung nicht verfügbar ist.",
                requirements: "Wenn die Verbindung fehlschlägt, aktiviere den CLI-Zugriff und die benachrichtigungsbasierte Integration in den BetterDisplay-Einstellungen.",
                notConfirmed: "Die Lautstärkeänderung konnte nicht bestätigt werden. Wähle „Erneut suchen“ und versuche es noch einmal."
            ),
            .italian: LocalizedFallbackCopy(
                controlMethodDescription: "Se i controlli del volume nel pannello di stato non riescono a gestire questo dispositivo, usa BetterDisplay.",
                displayDescription: "Scegli lo schermo corrispondente a questa uscita audio.",
                footnote: "Il controllo volume nativo di macOS ha la precedenza. Il metodo selezionato viene usato quando il controllo nativo non è disponibile.",
                requirements: "Se la connessione non riesce, attiva l’accesso alla CLI e l’integrazione basata su notifiche nelle impostazioni di BetterDisplay.",
                notConfirmed: "Impossibile confermare la modifica del volume. Seleziona “Rileva di nuovo” e riprova."
            ),
            .brazilianPortuguese: LocalizedFallbackCopy(
                controlMethodDescription: "Se os controles de volume do painel de status não conseguirem controlar este dispositivo, use o BetterDisplay.",
                displayDescription: "Escolha a tela correspondente a esta saída de áudio.",
                footnote: "O controle de volume nativo do macOS tem prioridade. O método selecionado é usado quando o controle nativo não estiver disponível.",
                requirements: "Se a conexão falhar, ative o acesso à CLI e a integração baseada em notificações nos ajustes do BetterDisplay.",
                notConfirmed: "Não foi possível confirmar a alteração de volume. Selecione “Detectar novamente” e tente outra vez."
            ),
            .russian: LocalizedFallbackCopy(
                controlMethodDescription: "Если элементы управления громкостью на панели состояния не управляют этим устройством, используйте BetterDisplay.",
                displayDescription: "Выберите дисплей, соответствующий этому аудиовыходу.",
                footnote: "Собственное управление громкостью macOS имеет приоритет. Выбранный способ используется, когда собственное управление недоступно.",
                requirements: "Если подключение не удаётся, включите доступ к CLI и интеграцию на основе уведомлений в настройках BetterDisplay.",
                notConfirmed: "Не удалось подтвердить изменение громкости. Выберите «Обнаружить снова» и повторите попытку."
            ),
            .arabic: LocalizedFallbackCopy(
                controlMethodDescription: "إذا لم تتمكن أدوات التحكم في مستوى الصوت بلوحة الحالة من التحكم في هذا الجهاز، فاستخدم BetterDisplay.",
                displayDescription: "اختر الشاشة المقابلة لخرج الصوت هذا.",
                footnote: "يحظى التحكم الأصلي في مستوى الصوت في macOS بالأولوية. تُستخدم الطريقة المحددة عندما لا يتوفر التحكم الأصلي.",
                requirements: "إذا فشل الاتصال، ففعّل وصول CLI والتكامل المستند إلى الإشعارات في إعدادات BetterDisplay.",
                notConfirmed: "تعذّر تأكيد تغيير مستوى الصوت. اختر «اكتشاف مجددًا» ثم حاول مرة أخرى."
            )
        ]

        XCTAssertEqual(expected.count, AppLanguage.allCases.count)
        for language in AppLanguage.allCases {
            let copy = try XCTUnwrap(
                expected[language],
                "Missing expected copy for \(language.rawValue)"
            )
            let bundle = try XCTUnwrap(Localization.resourceBundle(for: language))
            func value(_ key: LocalizationKey) -> String {
                bundle.localizedString(
                    forKey: key.rawValue,
                    value: nil,
                    table: nil
                )
            }

            XCTAssertEqual(
                value(.settingsAudioExternalVolumeControlMethodDescription),
                copy.controlMethodDescription,
                "\(language.rawValue) control-method copy must suggest BetterDisplay when the status panel cannot control the device"
            )
            XCTAssertEqual(
                value(.settingsAudioExternalVolumeDisplayDescription),
                copy.displayDescription,
                "\(language.rawValue) display copy must describe the linked display for this audio output"
            )
            XCTAssertEqual(
                value(.settingsAudioExternalVolumeFootnote),
                copy.footnote,
                "\(language.rawValue) footnote must keep native macOS volume control as the priority"
            )
            XCTAssertEqual(
                value(.settingsAudioExternalVolumeRequirements),
                copy.requirements,
                "\(language.rawValue) requirements must describe the actionable connection help"
            )
            XCTAssertEqual(
                value(.settingsAudioExternalVolumeStatusNotConfirmed),
                copy.notConfirmed,
                "\(language.rawValue) write-not-confirmed copy must point to Detect Again and retry"
            )
        }
    }

    private func outputIdentity(
        id: AudioDeviceID,
        uid: String
    ) -> PanelAudioDeviceID {
        PanelAudioDeviceID(id: id, uid: uid)
    }

    private func interactionIdentity(
        output: PanelAudioDeviceID,
        transitionGeneration: UInt64
    ) -> VolumeControlInteractionIdentity {
        VolumeControlInteractionIdentity(
            output: output,
            configuration: .default,
            transitionGeneration: transitionGeneration
        )
    }

    private func routeReading(
        device: AudioOutputDevice,
        scalar: Double
    ) -> VolumeReading {
        VolumeReading(
            scalar: scalar,
            isMuted: false,
            deviceName: device.name,
            currentDevice: device,
            canSetVolume: true,
            canMute: true
        )
    }

    private func makeEnglishLocalization() -> Localization {
        let suiteName = "BetterDisplayVolumeUIFixRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            TestUserDefaults.removeSuite(named: suiteName)
        }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }
}

private struct LocalizedFallbackCopy: Equatable {
    let controlMethodDescription: String
    let displayDescription: String
    let footnote: String
    let requirements: String
    let notConfirmed: String
}

private final class RouteReadingSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let readings: [VolumeReading]
    private var index = 0

    init(_ readings: [VolumeReading]) {
        self.readings = readings
    }

    func next() -> VolumeReading? {
        lock.withLock {
            guard index < readings.count else { return readings.last }
            defer { index += 1 }
            return readings[index]
        }
    }
}

@MainActor
private final class PassiveVolumeEventMonitor: VolumeEventMonitoring {
    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {}

    func reconcile() {}
    func recover() {}
    func stop() {}
}
