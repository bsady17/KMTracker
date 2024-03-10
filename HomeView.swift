import SwiftUI
import CoreLocation
import MapKit

struct Location: Codable {
    var latitude: Double
    var longitude: Double
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var distanceTraveled: Double = 0.0
    private var lastLocation: CLLocation?
    var onLocationUpdate: ((CLLocation) -> Void)?
    private var tripStartTime: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        checkLocationAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Requesting initial authorization
            locationManager.requestAlwaysAuthorization()
        case .restricted, .denied:
            // Handle cases where location services are restricted or denied
            break
        case .authorizedWhenInUse, .authorizedAlways:
            // Location services are already authorized
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        switch status {
        case .authorizedWhenInUse:
            print(".authorizedWhenInUse")
            break
        case .authorizedAlways:
            print("authorizedAlways")
            break
        case .denied, .restricted:
            print(".denied, .restricted")
            break
        case .notDetermined:
            // Request authorization again if not determined
            locationManager.requestAlwaysAuthorization()
        @unknown default:
            fatalError("Unhandled authorization status: \(status)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        if let lastLocation = self.lastLocation {
            let distance = newLocation.distance(from: lastLocation)
            distanceTraveled += distance / 1000.0 // Convert to kilometers
        }

        self.lastLocation = newLocation
        onLocationUpdate?(newLocation) // Call the closure with the new location
    }

    func startTrip() {
        distanceTraveled = 0.0
        lastLocation = nil
        tripStartTime = Date() // Record the start time
        locationManager.startUpdatingLocation()
    }
    
    var elapsedTime: TimeInterval {
        guard let start = tripStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func endTrip() {
        locationManager.stopUpdatingLocation()
        distanceTraveled = 0.0 // Reset the distance traveled
        lastLocation = nil // Reset the last known location
    }
    
    func startUpdatingLocation() {
            locationManager.startUpdatingLocation()
        }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

struct MapView: UIViewRepresentable {
    @Binding var userLocations: [CLLocation]
    var isStatic: Bool = false // New property to determine if the map should be static and grayscale

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        if isStatic {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isUserInteractionEnabled = false // Disable interactions for a static map
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateMapOverlay(mapView)
    }
    
    private func updateMapOverlay(_ mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays) // Remove existing overlays
        let coordinates = userLocations.map { $0.coordinate }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        
        if let firstLocation = userLocations.first {
            let region = MKCoordinateRegion(center: firstLocation.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
        }
    }
    
    // Add this method to enable drawing the polyline on the map
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct BottomSheetView<Content: View>: View {
    @Binding var isPresented: Bool
    let maxHeight: CGFloat
    let minHeight: CGFloat
    let content: Content
    @GestureState private var translation: CGFloat = 0

    init(isPresented: Binding<Bool>, minHeight: CGFloat, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                self.content
            }
            .frame(width: geometry.size.width, height: self.maxHeight, alignment: .top)
            .background(Color.white)
            .cornerRadius(15)
            .frame(height: geometry.size.height, alignment: .bottom)
            .offset(y: max(self.translation + (self.isPresented ? 0 : self.maxHeight - self.minHeight), 0))
            .gesture(
                DragGesture().updating(self.$translation) { value, state, _ in
                    state = value.translation.height
                }.onEnded { value in
                    let snapDistance = self.maxHeight * 0.25
                    if value.translation.height > snapDistance || value.translation.height < -snapDistance {
                        withAnimation(.interactiveSpring()) {
                            self.isPresented.toggle()
                        }
                    }
                }
            )
        }
    }
}

struct HomeView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var userLocations: [CLLocation] = []
    @State private var isTripStarted = false
    @State private var timerIsActive = false
    @State private var elapsedTime = 0 // Elapsed time in seconds
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var showingSaveConfirmation = false

    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var appSettings: AppSettings // Declare this to access AppSettings
    
    @State private var bottomSheetShown = true

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    if !isTripStarted {
                        MapView(userLocations: $userLocations, isStatic: true)
                            .grayscale(1.0)
                            .edgesIgnoringSafeArea(.all)
                    }
                    VStack {
                        if !isTripStarted {
                            Button(action: {
                                isTripStarted = true
                                timerIsActive = true
                                locationManager.startTrip()
                            }) {
                                VStack {
                                    Image(systemName: "play.fill")
                                        .font(.largeTitle) // Adjust the size of the play button
                                        .foregroundColor(.white)
                                    Text("Start Trip").font(.title2)
                                        .foregroundColor(.white)
                                        .fontWeight(.bold)
                                }
                                .frame(width: 150, height: 150)
                                .background(Color.green)
                                .opacity(0.9)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                            }
                        } else {
                            MapView(userLocations: $userLocations)
                                .frame(height: geometry.size.height) // Set to the full height of the screen
                                .edgesIgnoringSafeArea(.all)
                            
                            // START DRAWER
                            VStack {
                                BottomSheetView(isPresented: $bottomSheetShown, minHeight: 170, maxHeight: geometry.size.height * 0.35) {
                                    // Drawer handle
                                    RoundedRectangle(cornerRadius: 5)
                                        .frame(width: 40, height: 5) // Adjust the size as needed
                                        .foregroundColor(Color.gray.opacity(0.5))
                                        .padding(.top, 10)
                                    VStack(spacing: 10){
                                        Text("Driving Time: \(formatTime(elapsedTime))")
                                            .font(.system(size: 20))
                                            .fontWeight(.bold)
                                            .onReceive(timer) { _ in
                                                if timerIsActive {
                                                    elapsedTime += 1
                                                }
                                            }
                                        Text("Total KM: \(locationManager.distanceTraveled, specifier: "%.2f")")
                                            .font(.system(size: 20))
                                            .fontWeight(.bold)
                                    }
                                    .padding()
                                    
                                    HStack(spacing: 30) {
                                        // Pause button
                                        Button(action: {
                                            timerIsActive.toggle() // This toggles the timer's active state
                                            if timerIsActive {
                                                locationManager.startTrip() // Resume tracking
                                            } else {
                                                locationManager.endTrip() // Pause tracking
                                            }
                                        }) {
                                            Image(systemName: timerIsActive ? "pause.fill" : "play.fill") // Toggle icon based on timer state
                                                .foregroundColor(.black)
                                                .frame(width: 90, height: 90)
                                                .background(Color.yellow)
                                                .clipShape(Circle())
                                        }
                                        
                                        // End Trip button
                                        Button(action: {
                                            saveTrip() // Save the trip details first with the current elapsedTime
                                            isTripStarted = false
                                            timerIsActive = false
                                            elapsedTime = 0 // Then reset the elapsedTime
                                            locationManager.endTrip() // Stop tracking and reset distance
                                            userLocations.removeAll() // Clear recorded path
                                        }) {
                                            Image(systemName: "stop.fill")
                                                .foregroundColor(.white)
                                                .frame(width: 90, height: 90)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                        }
                                    }
                                }
                            }
                            .background(Color.gray)
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.18, alignment: .center) // Adjust this as needed
                            // END DRAWER
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Trip Saved!", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your trip has been successfully saved.")
        }
        .onAppear {
            locationManager.startUpdatingLocation()
            locationManager.onLocationUpdate = { newLocation in
                userLocations.append(newLocation)
            }
        }
        .onDisappear {
            locationManager.stopUpdatingLocation()
        }
    }

    func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func saveTrip() {
        let newTrip = Trip(context: managedObjectContext)
        newTrip.date = Date()
        newTrip.drivingTime = Int16(elapsedTime)
        newTrip.totalKMs = locationManager.distanceTraveled
        newTrip.isNew = true // Mark the trip as new

        let locations = userLocations.map { Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        if let encodedPath = try? JSONEncoder().encode(locations) {
            newTrip.pathData = encodedPath
        }

        do {
            try managedObjectContext.save()
            appSettings.isNewTripSaved = true
            showingSaveConfirmation = true
        } catch {
            print("Could not save the trip: \(error.localizedDescription)")
        }
    }
}
