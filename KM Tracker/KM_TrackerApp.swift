import SwiftUI
import CoreData
import Foundation
import Combine

class AppSettings: ObservableObject {
    @Published var isNewTripSaved: Bool = false
}

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "TripModel")
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        // Customize the tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.backgroundColor = UIColor.white.withAlphaComponent(0.5) // Semi-transparent white
        
        // For iOS 15 and later
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().standardAppearance = tabBarAppearance
        
        // For older versions of iOS
        UITabBar.appearance().backgroundImage = UIImage() // Transparent background
        UITabBar.appearance().shadowImage = UIImage() // Remove top shadow
        UITabBar.appearance().backgroundColor = UIColor.white.withAlphaComponent(0.5) // Semi-transparent white
    }
}

@main
struct KM_TrackerApp: App {
    let persistenceController = PersistenceController.shared
    let appSettings = AppSettings() // Instantiate AppSettings here

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appSettings) // Inject AppSettings into the environment
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var appSettings: AppSettings // Access AppSettings from the environment

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Start", systemImage: "car.fill")
                }
                .tag(0)

            TripsView()
                .badge(appSettings.isNewTripSaved ? "" : nil) // Attempt to show an empty badge
                .tabItem {
                    Label("Trips", systemImage: "map")
                }
                .tag(1)

            ReportsView()
                .tabItem {
                    Label("Reports", systemImage: "doc.plaintext")
                }
                .tag(2)
        }
    }
}

