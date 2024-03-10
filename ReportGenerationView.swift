import SwiftUI
import CoreData

struct ReportGenerationView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    @State private var reportType = "Monthly"
    @State private var selectedMonth: Int = 1
    @State private var selectedYear: Int = 2022
    @State private var availableYears: [Int] = []
    @State private var availableMonths: [Int] = []
    
    // State variables for custom date range
    @State private var startDate = Date()
    @State private var endDate = Date()
    
    // Fetch all trips to determine available years and months for reports
    @FetchRequest(
        entity: Trip.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.date, ascending: true)],
        animation: .default)
    private var trips: FetchedResults<Trip>
    
    var body: some View {
        Form {
            Picker("Report Type", selection: $reportType) {
                Text("Monthly").tag("Monthly")
                Text("Yearly").tag("Yearly")
                Text("Custom").tag("Custom")
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: reportType) {
                updateAvailableDates()
            }
            
            if reportType == "Monthly" {
                Section(header: Text("Select Year")) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .onChange(of: selectedYear) {
                        updateAvailableMonths()
                    }
                }
                
                Section(header: Text("Select Month")) {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(availableMonths, id: \.self) { month in
                            Text("\(DateFormatter().monthSymbols[month - 1])").tag(month)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
            } else if reportType == "Yearly" {
                // Yearly report selection UI
                Section(header: Text("Select Year")) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
            } else if reportType == "Custom" {
                // Custom date range selection UI
                Section(header: Text("Select Start Date")) {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .onChange(of: startDate) { // Adjust this closure to not use 'newStartDate'
                        if endDate < startDate {
                            endDate = startDate
                        }
                    }
                }

                Section(header: Text("Select End Date")) {
                    DatePicker(
                        "End Date",
                        selection: $endDate,
                        in: startDate...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .onChange(of: endDate) { // Adjust this closure to not use 'newEndDate'
                        if endDate < startDate {
                            startDate = endDate
                        }
                    }
                }
            }
            
            Button("Create Report") {
                generateReport()
            }
        }
        .onAppear {
            updateAvailableDates()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create Report")
                    .font(.title)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
            }
        }
    }
    
    private func updateAvailableDates() {
        let calendar = Calendar.current
        let years = trips.compactMap { trip in
            trip.date.map { calendar.component(.year, from: $0) }
        }
        
        availableYears = Array(Set(years)).sorted()
        
        if !availableYears.isEmpty {
            selectedYear = availableYears.first!
            updateAvailableMonths()
        }
    }
    
    private func updateAvailableMonths() {
        let calendar = Calendar.current
        availableMonths = trips.compactMap { trip in
            if let date = trip.date, calendar.component(.year, from: date) == selectedYear {
                return calendar.component(.month, from: date)
            }
            return nil
        }
        
        availableMonths = Array(Set(availableMonths)).sorted()
        
        if !availableMonths.isEmpty {
            selectedMonth = availableMonths.first!
        }
    }
    
    private func generateReport() {
        let newReport = Reports(context: viewContext)
        
        // Set the start and end dates for the report based on the report type
        let calendar = Calendar.current
        switch reportType {
        case "Monthly":
            if let startDate = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth)),
               let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) {
                newReport.startDate = startDate
                newReport.endDate = calendar.date(byAdding: .second, value: -1, to: endDate)
            }
        case "Yearly":
            if let startDate = calendar.date(from: DateComponents(year: selectedYear)) {
                newReport.startDate = startDate
                newReport.endDate = calendar.date(byAdding: .year, value: 1, to: startDate)?.addingTimeInterval(-1)
            }
        default: // Custom
            // Custom logic remains the same
            newReport.startDate = startDate
            newReport.endDate = endDate
            break
        }
        
        // Filter trips to those within the selected date range.
        let filteredTrips = trips.filter { trip in
            guard let tripDate = trip.date else { return false }
            return tripDate >= newReport.startDate! && tripDate <= newReport.endDate!
        }
        
        // Calculate the total kilometers and driving time.
        let totalKMs = filteredTrips.reduce(0.0) { $0 + $1.totalKMs }
        let totalDrivingTime = filteredTrips.reduce(0) { $0 + Int($1.drivingTime) } // Assuming `drivingTime` is stored in minutes or seconds.
        
        // Assign the calculated totals to the new report.
        newReport.totalKMs = totalKMs
        newReport.totalDrivingTime = Int16(totalDrivingTime)
        
        do {
            try viewContext.save()
        } catch {
            // Handle the error appropriately.
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}
