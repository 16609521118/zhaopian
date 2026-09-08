//
//  AppDelegate.swift
//  PhotoViewer
//
//  iOS 图片/视频查看器 - 应用入口
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 创建主窗口
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // 应用即将失去活跃状态
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 应用进入后台
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // 应用即将进入前台
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // 应用已成为活跃状态
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 应用即将终止
    }
}
