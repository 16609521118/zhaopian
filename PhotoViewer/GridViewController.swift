//
//  GridViewController.swift
//  PhotoViewer
//
//  单个挂载文件夹的媒体网格（3 列），缩略图异步生成并缓存。
//  点击进入全屏查看器。离开时释放文件夹安全作用域访问。
//

import UIKit

final class GridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {

    private let folder: MountedFolder
    private var items: [MediaItem] = []
    private var collectionView: UICollectionView!
    private let store = FolderStore.shared
    private let emptyLabel = UILabel()

    init(folder: MountedFolder) {
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = folder.name
        view.backgroundColor = .systemBackground

        let spacing: CGFloat = 2
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: spacing, left: 0, bottom: spacing, right: 0)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GridCell.self, forCellWithReuseIdentifier: "GridCell")
        collectionView.backgroundColor = .systemBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        emptyLabel.text = "此文件夹中没有照片或视频"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // 异步枚举媒体（大文件夹不阻塞主线程）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let items = self.store.media(in: self.folder)
            DispatchQueue.main.async {
                self.items = items
                self.emptyLabel.isHidden = !items.isEmpty
                self.collectionView.reloadData()
            }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let cols: CGFloat = 3
        let spacing: CGFloat = 2
        let totalSpacing = spacing * (cols - 1)
        let size = (view.bounds.width - totalSpacing) / cols
        layout.itemSize = CGSize(width: size, height: size)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 离开此文件夹时释放安全作用域访问（返回列表或切换时）
        if isMovingFromParent || isBeingDismissed {
            store.release(folder)
        }
    }

    // MARK: - Collection view

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GridCell", for: indexPath) as! GridCell
        cell.configure(item: items[indexPath.item], folder: folder, store: store)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let viewer = ViewerViewController(folder: folder, items: items, startIndex: indexPath.item)
        viewer.modalPresentationStyle = .fullScreen
        present(viewer, animated: true)
    }
}

// MARK: - 网格单元

final class GridCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let badge = UILabel()
    private var itemID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        badge.text = "▶"
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        badge.isHidden = true
        itemID = nil
    }

    func configure(item: MediaItem, folder: MountedFolder, store: FolderStore) {
        itemID = item.id
        badge.isHidden = (item.type != .video)
        let size = bounds.size
        store.thumbnail(for: item, in: folder, size: size) { [weak self] image in
            guard self?.itemID == item.id else { return }
            self?.imageView.image = image
        }
    }
}
