import SwiftUI
import CoreData
import CoreLocation
import MapKit

struct ReportDetailView: View {
    var report: Report
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest var trips: FetchedResults<Trip>
    @State private var showingEmailExport = false
    
    // Custom initializer to dynamically set the fetch request based on report dates
    init(report: Report) {
        self.report = report
        let calendar = Calendar.current

        // Adjust the start date to the beginning of the day
        let startDate = calendar.startOfDay(for: report.startDate)

        // Ensure the end date covers the entire end day
        let endDate: Date
        if calendar.isDate(report.endDate, inSameDayAs: report.startDate) {
            // If start and end date are the same, adjust end date to the end of the day
            endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: report.startDate)!
        } else {
            // For a range, adjust end date to include the entire end day
            endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: report.endDate)!
        }

        self._trips = FetchRequest<Trip>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Trip.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
        )
    }

    // Calculate total driving time and KMs dynamically
    private var totalDrivingTime: Int {
        trips.reduce(0) { $0 + Int($1.drivingTime) }
    }
    
    private var totalKMs: Double {
        trips.reduce(0.0) { $0 + $1.totalKMs }
    }

    private let itemFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        List {
            Section(header: Text("Report Summary")) {
                Text(report.title).bold()
                Text("Driving Time: \(formatTimeInterval(totalDrivingTime))").bold()
                Text("Total KMs: \(totalKMs, specifier: "%.2f")").bold()
            }
            
            Section(header: Text("Daily Breakdown")) {
                ForEach(trips, id: \.self) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        VStack(alignment: .leading) {
                            Text(trip.date!, formatter: itemFormatter).font(.headline)
                            Text("Driving Time: \(formatTimeFromSeconds(Int(trip.drivingTime)))").font(.subheadline)
                            Text("Total KMs: \(trip.totalKMs, specifier: "%.2f")").font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(report.title)
                    .font(.title2) // Customize this font size as needed
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Export") {
                    showingEmailExport = true
                }
                .sheet(isPresented: $showingEmailExport) {
                    ReportEmailExportView(
                        isPresented: $showingEmailExport,
                        reportDetails: prepareReportDetails(),
                        reportTitle: report.title,
                        csvData: self.generateCSVData() ?? Data()
                    )
                }
            }
        }
    }
    
    func formatTimeInterval(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func prepareReportDetails() -> String {
        // Format the report's details into a string
        // This should include the information you want to send in the email
        // For example, report title, total driving time, total KMs, and any other relevant information
        var details = "Report: \(report.title )\n"
        details += "Total Driving Time: \(formatTimeInterval(totalDrivingTime))\n"
        details += "Total KMs: \(String(format: "%.2f", totalKMs)) KM\n"
        // Add more details as needed
        return details
    }
    
    private func generateCSVData() -> Data? {
        let header = "Date,Driving Time,Total KMs\n"
        let csvString = trips.reduce(into: header) { csv, trip in
            // Adjust the date format to include the full date including the year
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium // Adjust this based on your preference
            dateFormatter.timeStyle = .none
            
            if let tripDate = trip.date {
                let formattedDate = dateFormatter.string(from: tripDate)
                // Enclose the date in quotes to ensure it's treated as a single field in CSV
                let tripData = "\"\(formattedDate)\",\(formatTimeInterval(Int(trip.drivingTime))),\(trip.totalKMs)\n"
                csv += tripData
            }
        }
        
        return csvString.data(using: .utf8)
    }
}

struct ReportEmailExportView: View {
    @Binding var isPresented: Bool
    var reportDetails: String
    var reportTitle: String
    var csvData: Data
    
    @State private var email = ""
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
                        sendEmail(reportDetails: reportDetails, to: email, csvData: csvData) { _ in
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
                    Text("Export \(reportTitle)") // Dynamically set the title
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
    
    func sendEmail(reportDetails: String, to email: String, csvData: Data, completion: @escaping (Bool) -> Void) {
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

        let formData = createFormData(boundary: boundary, email: email, reportDetails: reportDetails, csvData: csvData)
        request.httpBody = formData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.alertMessage = "Failed to send email: \(error.localizedDescription)"
                    self.showFailureAlert = true
                    completion(false)
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.alertMessage = "Email sent successfully."
                    self.showSuccessAlert = true
                    completion(true)
                } else {
                    self.alertMessage = "Failed to send email. Please try again later."
                    self.showFailureAlert = true
                    completion(false)
                }
            }
        }
        task.resume()
    }
    func createFormData(boundary: String, email: String, reportDetails: String, csvData: Data) -> Data {
        var body = Data()
        
        // Adjusted parameters to match TripsView
        let parameters: [String: String] = [
            "from": "KM Tracker App <mailgun@sandbox359c64de15dd46b485d77c8dacd72d45.mailgun.org>", // Adjusted to match TripsView
            "to": email,
            "subject": "Exported Trip Details", // Or adjust as needed to match the intended subject
            "text": reportDetails
        ]
        
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        
        // Add the CSV file attachment with an appropriate name
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"attachment\"; filename=\"report_details.csv\"\r\n")
        body.append("Content-Type: text/csv\r\n\r\n")
        body.append(csvData)
        body.append("\r\n")
        
        // Boundary end
        body.append("--\(boundary)--\r\n")
        return body
    }
}


