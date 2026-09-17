import SwiftUI
import MobileVLCKit

struct VLCPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let vc = VLCPlayerViewController()
        vc.configure(with: url)
        return vc
    }

    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {}
}

final class VLCPlayerViewController: UIViewController {
    private var player: VLCMediaPlayer?
    private lazy var playButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("暂停", for: .normal)
        b.setTitle("播放", for: .selected)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private lazy var slider: UISlider = {
        let s = UISlider()
        s.addTarget(self, action: #selector(onSliderChanged(_:)), for: .valueChanged)
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var timeLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var timer: Timer?

    func configure(with url: URL) {
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        player = VLCMediaPlayer()
        player?.media = media
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let renderView = UIView()
        renderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(renderView)
        view.addSubview(slider)
        view.addSubview(timeLabel)
        view.addSubview(playButton)

        NSLayoutConstraint.activate([
            renderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            renderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            renderView.bottomAnchor.constraint(equalTo: slider.topAnchor, constant: -12),

            slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -6),

            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            timeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            playButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        player?.drawable = renderView
        player?.play()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] _ in
            self?.refreshUI()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.stop()
        timer?.invalidate()
        timer = nil
    }

    private func refreshUI() {
        guard let player = player else { return }
        playButton.isSelected = !player.isPlaying
        let current = player.time.value.doubleValue
        let total = player.media?.length.value.doubleValue ?? 1
        slider.maximumValue = Float(max(total, 1))
        slider.value = Float(current)
        timeLabel.text = "\(formatTime(current)) / \(formatTime(total))"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    @objc private func togglePlay() {
        guard let player = player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    @objc private func onSliderChanged(_ sender: UISlider) {
        guard let player = player else { return }
        player.time = VLCTime(int: Int32(sender.value))
    }
}
