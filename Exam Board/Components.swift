import AppKit
import Combine
import SwiftUI

public final class ExamBoardViewModel: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    
    @Published var isTimerEditing = false
    @Published var isTimerRunning = false
    @Published var configuredSeconds = 0
    @Published var remainingSeconds = 0
    @Published var currentTimeText = ""
    @Published var hourText = "00"
    @Published var minuteText = "00"
    @Published var secondText = "00"
    @Published var voiceEnabled = false
    @Published var scratchpadFontText = "14"
    @Published var scratchpadFontSize: CGFloat = 14
    @Published var scratchpadText = ""
    
    private var currentTimeTimer: Timer?
    private var countdownTimer: Timer?
    private let speechSynthesizer = NSSpeechSynthesizer()
    private var speechQueue: [String] = []
    private var announcedMilestones = Set<Int>()
    
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "hh:mm:ss a"
        return formatter
    }()
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        currentTimeText = clockFormatter.string(from: Date())
        startCurrentTimeTimer()
    }
    
    deinit {
        currentTimeTimer?.invalidate()
        countdownTimer?.invalidate()
    }
    
    var countdownText: String { Self.format(seconds: remainingSeconds) }
    
    var startActionTitle: String {
        if remainingSeconds == 0 && configuredSeconds > 0 { return "OK" }
        if isTimerRunning { return "Pause" }
        if remainingSeconds < configuredSeconds { return "Resume" }
        return "Start"
    }
    
    var voiceActionTitle: String { voiceEnabled ? "Mute" : "Voice" }
    
    var timerActionTitle: String {
        if isTimerRunning { return "Reset" }
        return isTimerEditing ? "Apply" : "Set"
    }
    
    var timeProgress: Double {
        guard configuredSeconds > 0 else { return 1 }
        return max(0, min(1, Double(remainingSeconds) / Double(configuredSeconds)))
    }
    
    public func handleTimerAction() {
        if isTimerRunning {
            resetTimer()
        } else if isTimerEditing {
            applyTimerFromFields()
        } else {
            beginEditingTimer()
        }
    }
    
    public func toggleTimerRunning() {
        if remainingSeconds == 0 && configuredSeconds > 0 {
            acknowledgeFinishedTimer()
        } else if isTimerRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }
    
    public func toggleVoice() {
        voiceEnabled.toggle()
        if !voiceEnabled { stopSpeakingImmediately() }
    }
    
    public func applyScratchpadFont() {
        let trimmed = scratchpadFontText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = CGFloat(Int(trimmed) ?? 14)
        scratchpadFontSize = max(1, fontSize)
        scratchpadFontText = String(Int(scratchpadFontSize))
    }
    
    // MARK: Timer components
    
    private func sanitizeTimerField(_ value: String, maxLength: Int = 4) -> String {
        String(value.filter { $0.isNumber }.prefix(maxLength))
    }
    
    public func currentTimerFieldBinding(_ keyPath: ReferenceWritableKeyPath<ExamBoardViewModel, String>,
                                         maxLength: Int) -> Binding<String> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = self.sanitizeTimerField($0, maxLength: maxLength) }
        )
    }
    
    public func fontFieldBinding() -> Binding<String> {
        currentTimerFieldBinding(\ExamBoardViewModel.scratchpadFontText, maxLength: 4)
    }
    
    private func countdownTick() {
        guard isTimerRunning else { return }
        
        let previousSeconds = remainingSeconds
        remainingSeconds = max(0, remainingSeconds - 1)
        
        announceMilestones(previousSeconds: previousSeconds, currentSeconds: remainingSeconds)
        if remainingSeconds == 0 { finishTimer() }
    }
    
    private func makeRepeatingTimer(_ tick: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
    
    private func startCurrentTimeTimer() {
        currentTimeTimer?.invalidate()
        currentTimeTimer = makeRepeatingTimer { [weak self] in
            self?.currentTimeText = self?.clockFormatter.string(from: Date()) ?? ""
        }
    }
    
    private func beginEditingTimer() {
        isTimerEditing = true
        hourText = String(format: "%02d", configuredSeconds / 3600)
        minuteText = String(format: "%02d", (configuredSeconds % 3600) / 60)
        secondText = String(format: "%02d", configuredSeconds % 60)
    }
    
    private func applyTimerFromFields() {
        let hours = Int(hourText) ?? 0
        let minutes = Int(minuteText) ?? 0
        let seconds = Int(secondText) ?? 0
        let clampedMinutes = max(0, min(59, minutes))
        let clampedSeconds = max(0, min(59, seconds))
        
        configuredSeconds = max(0, hours) * 3600 + clampedMinutes * 60 + clampedSeconds
        remainingSeconds = configuredSeconds
        announcedMilestones.removeAll()
        isTimerEditing = false
    }
    
    private func resetTimer() {
        stopCountdownTimer()
        isTimerRunning = false
        isTimerEditing = false
        remainingSeconds = configuredSeconds
        announcedMilestones.removeAll()
    }
    
    private func pauseTimer() {
        stopCountdownTimer()
        isTimerRunning = false
    }
    
    private func acknowledgeFinishedTimer() {
        remainingSeconds = configuredSeconds
        announcedMilestones.removeAll()
    }
    
    private func startTimer() {
        guard remainingSeconds > 0 else { return }
        
        let isInitialStart = remainingSeconds == configuredSeconds
        
        isTimerEditing = false
        isTimerRunning = true
        startCountdownTimer()
        
        if voiceEnabled {
            if isInitialStart { speak("You may begin.") }
            announceMilestones(previousSeconds: remainingSeconds + 1, currentSeconds: remainingSeconds)
        }
    }
    
    private func finishTimer() {
        stopCountdownTimer()
        isTimerRunning = false
        if voiceEnabled { speak("Please stop writing, and hand in your question booklet.") }
    }
    
    private func startCountdownTimer() {
        stopCountdownTimer()
        countdownTimer = makeRepeatingTimer { [weak self] in self?.countdownTick() }
    }
    
    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    // MARK: Voice components
    
    private func announceMilestones(previousSeconds: Int, currentSeconds: Int) {
        guard voiceEnabled else { return }
        
        let milestones: [(seconds: Int, message: String)] = [(3600, "You have one hour left."),
                                                             (1800, "You have thirty minutes left."),
                                                             (900, "You have fifteen minutes left."),
                                                             (300, "You have five minutes left."),
                                                             (120, "You have two minutes left."),
                                                             (60, "You have one minute left.")
        ]
        
        for milestone in milestones where !announcedMilestones.contains(milestone.seconds) {
            if previousSeconds >= milestone.seconds && currentSeconds <= milestone.seconds {
                announcedMilestones.insert(milestone.seconds)
                speak(milestone.message)
            }
        }
    }
    
    private func speak(_ message: String) {
        guard voiceEnabled else { return }
        speechQueue.append(message)
        if !speechSynthesizer.isSpeaking { speakNextMessage() }
    }
    
    private func speakNextMessage() {
        guard !speechQueue.isEmpty else { return }
        let message = speechQueue.removeFirst()
        speechSynthesizer.startSpeaking(message)
    }
    
    private func stopSpeakingImmediately() {
        speechQueue.removeAll()
        speechSynthesizer.stopSpeaking()
    }
    
    public func speechSynthesizer(_ synthesizer: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        speakNextMessage()
    }
    
    private static func format(seconds totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
}

struct ContentView: View {
    
    @ObservedObject var viewModel: ExamBoardViewModel
    @State private var committedLeftWidth: CGFloat?
    @GestureState private var dragTranslation: CGFloat = 0
    
    private let initialSplitFraction: CGFloat = 0.45
    private let minPaneWidth: CGFloat = 370
    private let dividerHitWidth: CGFloat = 10
    private let dividerLineWidth: CGFloat = 1
    
    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let baseLeftWidth = committedLeftWidth ?? totalWidth * initialSplitFraction
            let leftWidth = clampedLeftWidth(baseLeftWidth + dragTranslation, totalWidth: totalWidth)
            let rightWidth = max(minPaneWidth, totalWidth - leftWidth - dividerLineWidth)
            
            HStack(spacing: 0) {
                timerSection.frame(width: leftWidth, height: proxy.size.height)
                resizeHandle(totalWidth: totalWidth)
                textpadSection.frame(width: rightWidth, height: proxy.size.height)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.frame(minWidth: 800, minHeight: 500)
    }
    
    private func clampedLeftWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let upperBound = max(minPaneWidth, totalWidth - minPaneWidth - dividerLineWidth)
        return min(max(width, minPaneWidth), upperBound)
    }
    
    private var timeRemainingPercent: Int {
        Int((viewModel.timeProgress * 100).rounded())
    }
    
    private func resizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle().fill(Color.secondary.opacity(0.25))
            .frame(width: dividerLineWidth)
            .frame(width: dividerHitWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }.gesture(DragGesture().updating($dragTranslation) { value, state, _ in
                state = value.translation.width
            }.onEnded { value in
                let base = committedLeftWidth ?? totalWidth * initialSplitFraction
                committedLeftWidth = clampedLeftWidth(base + value.translation.width, totalWidth: totalWidth)
            }
        )
    }
    
    // MARK: Timer area
    
    private var timerSection: some View {
        VStack(spacing: 75) {
            VStack(spacing: 10) {
                Text("Time Remaining").font(.headline)
                
                Group {
                    if viewModel.isTimerEditing {
                        editableTimerFields
                    } else {
                        Text(viewModel.countdownText).font(.system(size: 65, weight: .semibold, design: .monospaced))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    
                    progressBar.frame(height: 25)
                    Text("\(timeRemainingPercent)%").font(.system(size: 20, weight: .medium, design: .monospaced))
                }.frame(maxWidth: .infinity, alignment: .center)
            }
            
            VStack(spacing: 5) {
                Text("Current Time").font(.headline)
                Text(viewModel.currentTimeText).font(.system(size: 45, weight: .medium, design: .monospaced))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private var editableTimerFields: some View {
        HStack(spacing: 5) {
            timerField(text: viewModel.currentTimerFieldBinding(\ExamBoardViewModel.hourText, maxLength: 4), width: 72)
            Text(":").font(.system(size: 52, weight: .semibold, design: .monospaced))
            timerField(text: viewModel.currentTimerFieldBinding(\ExamBoardViewModel.minuteText, maxLength: 2), width: 58)
            Text(":").font(.system(size: 52, weight: .semibold, design: .monospaced))
            timerField(text: viewModel.currentTimerFieldBinding(\ExamBoardViewModel.secondText, maxLength: 2), width: 58)
        }
    }
    
    private func timerField(text: Binding<String>, width: CGFloat) -> some View {
        TextField("00", text: text).font(.system(size: 38, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textFieldStyle(RoundedBorderTextFieldStyle())
    }
    
    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                    .frame(width: proxy.size.width * CGFloat(viewModel.timeProgress))
            }
        }
    }
    
    // MARK: Textpad area
    
    private var textpadSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button(viewModel.timerActionTitle) {
                    viewModel.handleTimerAction()
                }.disabled(viewModel.isTimerEditing && viewModel.isTimerRunning)
                
                Button(viewModel.startActionTitle) {
                    viewModel.toggleTimerRunning()
                }.disabled(viewModel.isTimerEditing)
                
                Button(viewModel.voiceActionTitle) { viewModel.toggleVoice() }
                
                Text("Font (pt):")
                TextField("14", text: viewModel.fontFieldBinding(), onCommit: {
                    viewModel.applyScratchpadFont()
                }).frame(width: 35).textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            TextpadTextView(text: $viewModel.scratchpadText, fontSize: viewModel.scratchpadFontSize).overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        }.padding(24)
    }
    
}

public struct TextpadTextView: NSViewRepresentable {
    
    @Binding var text: String
    var fontSize: CGFloat
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        
        let updatedFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        if textView.font != updatedFont { textView.font = updatedFont }
        
        if context.coordinator.text.wrappedValue != text { context.coordinator.text.wrappedValue = text }
    }
    
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
    
}
