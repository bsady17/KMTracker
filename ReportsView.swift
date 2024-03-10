import SwiftUI
import CoreData

struct Report: Identifiable {
    let id: UUID
    var title: String
    var summary: String
    var startDate: Date
    var endDate: Date
    var totalDrivingTime: Int // Assuming total driving time is stored in seconds
    var totalKMs: Double
    var lastUpdated: Date // New property to store the last updated date
}

func formatTimeInterval(_ totalSeconds: Int) -> String {
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}

struct ReportsView: View {
    @FetchRequest(
        entity: Reports.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Reports.startDate, ascending: true)],
        animation: .default)
    private var fetchedReports: FetchedResults<Reports>

    @Environment(\.managedObjectContext) private var viewContext

    var reports: [Report] {
        // Assuming you have a way to fetch trips that match each report's timeframe
        // This code snippet demonstrates the concept and may need adjustments for your specific data model
        fetchedReports.map { reportEntity in
            let safeStartDate = reportEntity.startDate ?? Date()
            let safeEndDate = reportEntity.endDate ?? Date()
            
            // Fetch trips within the report's timeframe
            let fetchRequest: NSFetchRequest<Trip> = Trip.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date <= %@", safeStartDate as NSDate, safeEndDate as NSDate)
            let trips = (try? viewContext.fetch(fetchRequest)) ?? []

            // Calculate totals
            let totalDrivingTime = trips.reduce(0) { $0 + Int($1.drivingTime) }
            let totalKMs = trips.reduce(0.0) { $0 + $1.totalKMs }

            // Continue constructing Report as before, now including dynamic totals
            let title = "\(dateFormatter.string(from: safeStartDate)) - \(dateFormatter.string(from: safeEndDate))"
            let summary = "Driving Time: \(formatTimeInterval(totalDrivingTime))\nTotal KMs: \(String(format: "%.2f", totalKMs))"
            
            return Report(
                id: UUID(), // Adjust as necessary, e.g., use reportEntity's ID if available
                title: title,
                summary: summary,
                startDate: safeStartDate,
                endDate: safeEndDate,
                totalDrivingTime: totalDrivingTime,
                totalKMs: totalKMs,
                lastUpdated: reportEntity.lastUpdated ?? Date() // Handle lastUpdated similarly
            )
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(reports) { report in
                    NavigationLink(destination: ReportDetailView(report: report)) {
                        VStack(alignment: .leading) {
                            Text(report.title)
                                .font(.headline)
                            Text(report.summary)
                                .font(.subheadline)
                            // Add the last updated text below the summary
                            Text("Last Updated: \(dateFormatter.string(from: report.lastUpdated))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .onDelete(perform: deleteReports) // Allows deletion of reports
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reports")
                        .font(.title) // Customize this font size as needed
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: ReportGenerationView()) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            let report = fetchedReports[index]
            viewContext.delete(report)
        }
        
        do {
            try viewContext.save()
        } catch {
            // Handle the save error, perhaps logging or showing an alert to the user
        }
    }
}
