import SwiftUI
import CoreData
import CoreLocation
import MapKit

struct TripsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.date, ascending: false)],
        animation: .default)
    private var trips: FetchedResults<Trip>
    @EnvironmentObject var appSettings: AppSettings // Add this line

    var body: some View {
        NavigationView {
            List {
                ForEach(trips, id: \.self) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)
                        .onAppear {
                            // This block will be executed when the TripDetailView appears
                            if trip.isNew {
                                trip.isNew = false // Update the trip's isNew status
                                // Save the context to persist changes
                                do {
                                    try viewContext.save()
                                } catch {
                                    // Handle save error, e.g., show an error message to the user
                                    print("Failed to save context: \(error.localizedDescription)")
                                }
                            }
                        }
                    ) {
                        HStack {
                            // Conditionally show a badge if the trip is new
                            if trip.isNew {
                                // This is a simple badge indicator, customize as needed
                                Text("")
                                    .padding(5)
                                    .background(Color.red)
                                    .foregroundColor(Color.white)
                                    .clipShape(Circle())
                            }
                            Text(trip.date!, formatter: itemFormatter)
                        }
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Trips")
                        .font(.title) // Customize this font size as needed
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                }
            }
            .navigationBarTitleDisplayMode(.inline) // Makes the title inline if preferred.
            .navigationBarItems(trailing: EditButton())
        }
        .onAppear {
            appSettings.isNewTripSaved = false // Reset the isNewTripSaved flag when the view appears
        }
    }
    
    private func deleteTrips(offsets: IndexSet) {
        withAnimation {
            offsets.map { trips[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Handle the error, e.g., show an alert.
                print(error.localizedDescription)
            }
        }
    }
}

struct CustomMapView: UIViewRepresentable {
    var pathCoordinates: [CLLocationCoordinate2D]
    var isStatic: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        if isStatic {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isUserInteractionEnabled = false
        } else {
            mapView.isScrollEnabled = true
            mapView.isZoomEnabled = true
            mapView.isUserInteractionEnabled = true
        }
        
        // Add the polyline overlay to the map if pathCoordinates are provided
        let polyline = MKPolyline(coordinates: pathCoordinates, count: pathCoordinates.count)
        mapView.addOverlay(polyline)
        
        // Optionally, set the map region to the polyline area
        if let firstCoordinate = pathCoordinates.first {
            let region = MKCoordinateRegion(center: firstCoordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
            mapView.setRegion(region, animated: true)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Handle dynamic updates if necessary
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self) // Correctly references CustomMapView
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView // Corrected to reference CustomMapView
        
        init(_ parent: CustomMapView) { // Corrected to accept CustomMapView
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue // Customize polyline color
                renderer.lineWidth = 4.0 // Customize polyline width
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

func formatTimeFromSeconds(_ totalSeconds: Int) -> String {
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

struct TripDetailView: View {
    var trip: Trip // Assume Trip is your CoreData entity. Adapt as needed.
    @State private var showingEmailExport = false
    @Environment(\.managedObjectContext) private var viewContext
    // Assume you have access to trips data or a way to fetch or receive it here
        
    var pathCoordinates: [CLLocationCoordinate2D] {
        guard let pathData = trip.pathData, // Ensure you have a property for this
              let locations = try? JSONDecoder().decode([Location].self, from: pathData) else {
            return []
        }
        return locations.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack {
                    Text("Driving Time:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("\(formatTimeFromSeconds(Int(trip.drivingTime)))")
                        .fontWeight(.bold)
                        .font(.title2)
                }
                Spacer()
                VStack {
                    Text("Total KMs:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("\(trip.totalKMs, specifier: "%.2f") KM")
                        .fontWeight(.bold)
                        .font(.title2)
                }
            }
            .padding(.bottom, 10) // Add some spacing between the stats and the map
            CustomMapView(pathCoordinates: pathCoordinates, isStatic: false)
                //.disabled(true) // If you want to ensure the map is not interactive
                .clipShape(RoundedRectangle(cornerRadius: 20)) // Apply rounded corners
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Export") {
                    self.showingEmailExport = true
                }
                .sheet(isPresented: $showingEmailExport) {
                    // Present EmailExportView with the generated CSV data
                    EmailExportView(
                        isPresented: $showingEmailExport,
                        tripDetails: prepareTripDetails(),
                        tripDate: trip.date != nil ? itemFormatter.string(from: trip.date!) : "Unknown Date",
                        csvData: self.generateCSVData() ?? Data() // Ensure csvData is generated here
                    )
                }
            }
            ToolbarItem(placement: .principal) {
                Text(trip.date!, formatter: itemFormatter)
                    .font(.title) // Customize this font size as needed
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
            }
        }
    }
    
    func prepareTripDetails() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        
        let dateStr = trip.date != nil ? dateFormatter.string(from: trip.date!) : "Unknown Date"
        let drivingTimeStr = formatTimeFromSeconds(Int(trip.drivingTime))
        let totalKMsStr = String(format: "%.2f", trip.totalKMs)
        
        return """
        Trip Details:
        Date: \(dateStr)
        Driving Time: \(drivingTimeStr)
        Total Kilometers: \(totalKMsStr) KM
        """
    }
    
    private func generateCSVData() -> Data? {
        let csvString = "Date,Driving Time,Total KMs\n" + // Example CSV header
        "\(trip.date!),\(trip.drivingTime),\(trip.totalKMs)\n" // Simplified; you'll want to loop through your trips if generating a report for multiple trips
        
        return csvString.data(using: .utf8)
    }
    
}

struct EmailExportView: View {
    @Binding var isPresented: Bool
    var tripDetails: String
    var tripDate: String
    var csvData: Data
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showSuccessAlert = false
    @State private var showFailureAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Enter your email")) {
                    TextField("Email address", text: $email)
                }
                Section {
                    Button("Send Report") {
                        sendEmail(tripDetails: tripDetails, to: email, csvData: csvData) { _ in
                        }
                    }
                    .alert("Email sent!", isPresented: $showSuccessAlert) {
                        Button("OK", role: .cancel) { isPresented = false }
                    } message: {
                        Text(alertMessage)
                    }
                    .alert("Something went wrong :(", isPresented: $showFailureAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(alertMessage)
                    }
                }
            }
            .navigationTitle("") // Removes the navigation bar title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Export \(tripDate)") // Dynamically set the title
                        .font(.title3)
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
        }
    }
    
    @State private var email = ""
    
    func sendEmail(tripDetails: String, to email: String, csvData: Data, completion: @escaping (Bool) -> Void) {
        let apiKey = "ae8b8a288c2bdbee3e5f2c4d75c125e3-2c441066-c67d0737"
        let domain = "sandbox359c64de15dd46b485d77c8dacd72d45.mailgun.org"
        let url = URL(string: "https://api.mailgun.net/v3/\(domain)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let credentials = Data("api:\(apiKey)".utf8).base64EncodedString()
        request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        
        // Generate boundary string using a unique string
        let boundary = "Boundary-\(UUID().uuidString)"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let formData = createFormData(boundary: boundary, email: email, tripDetails: tripDetails, csvData: csvData)
        request.httpBody = formData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    // Handle error case
                    self.alertMessage = "Failed to send email: \(error.localizedDescription)"
                    self.showFailureAlert = true // Use showFailureAlert for errors
                    completion(false)
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Success case
                    self.alertMessage = "Email sent successfully."
                    self.showSuccessAlert = true
                    completion(true)
                } else {
                    // Handle server error or unsuccessful response
                    self.alertMessage = "Failed to send email. Please try again later."
                    self.showFailureAlert = true
                    completion(false)
                }
            }
        }
        task.resume()
    }
    
    func createFormData(boundary: String, email: String, tripDetails: String, csvData: Data) -> Data {
        var body = Data()
        
        // Parameters
        let parameters: [String: String] = [
            "from": "KM Tracker App <mailgun@sandbox359c64de15dd46b485d77c8dacd72d45.mailgun.org>",
            "to": email,
            "subject": "Exported Trip Details",
            "text": tripDetails
        ]
        
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        
        // CSV file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"attachment\"; filename=\"trip_details.csv\"\r\n")
        body.append("Content-Type: text/csv\r\n\r\n")
        body.append(csvData)
        body.append("\r\n")
        
        // Boundary end
        body.append("--\(boundary)--\r\n")
        return body
    }
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter
}()
