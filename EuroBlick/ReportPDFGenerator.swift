import PDFKit
import SwiftUI
import Foundation
import UIKit

class ReportPDFGenerator {
    let monthlyData: [MonthlyData]
    let categoryData: [CategoryData]
    let forecastData: [ForecastData]
    let selectedMonth: String
    let customDateRange: (start: Date, end: Date)?
    
    init(monthlyData: [MonthlyData], categoryData: [CategoryData], forecastData: [ForecastData], selectedMonth: String, customDateRange: (start: Date, end: Date)?) {
        self.monthlyData = monthlyData
        self.categoryData = categoryData
        self.forecastData = forecastData
        self.selectedMonth = selectedMonth
        self.customDateRange = customDateRange
    }
    
    static func generatePDF(
        monthlyData: [MonthlyData],
        categoryData: [CategoryData],
        forecastData: [ForecastData],
        incomeChartImage: UIImage?,
        categoryChartImage: UIImage?
    ) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator as String: "EuroBlick",
            kCGPDFContextAuthor as String: "User"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth: CGFloat = 595.2 // A4 Breite in Punkten (8.27 Zoll)
        let pageHeight: CGFloat = 841.8 // A4 Höhe in Punkten (11.69 Zoll)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.black
            ]
            let titleString = "Finanzbericht"
            let titleSize = titleString.size(withAttributes: titleAttributes)
            titleString.draw(at: CGPoint(x: (pageWidth - titleSize.width) / 2, y: 20), withAttributes: titleAttributes)
            
            var yOffset: CGFloat = 60
            
            // Einnahmen und Ausgaben
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.black
            ]
            let sectionString = "Einnahmen und Ausgaben"
            sectionString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 30
            
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            for data in monthlyData {
                let monthString = "Monat: \(data.month)"
                monthString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
                
                let incomeString = "Einnahmen: \(String(format: "%.2f €", data.income))"
                incomeString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
                
                let expensesString = "Ausgaben: \(String(format: "%.2f €", data.expenses))"
                expensesString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
                
                let surplusString = "Überschuss: \(String(format: "%.2f €", data.surplus))"
                surplusString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 25
            }
            
            // Kategorien
            let categorySectionString = "Ausgaben nach Kategorie"
            categorySectionString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 30
            
            for category in categoryData {
                let categoryString = "\(category.name): \(String(format: "%.2f €", category.value))"
                categoryString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
            }
            
            // Prognose
            if let forecast = forecastData.first {
                yOffset += 20
                let forecastSectionString = "Prognostizierter Kontostand am Monatsende"
                forecastSectionString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: sectionAttributes)
                yOffset += 30
                
                let einnahmenString = "Einnahmen: \(String(format: "%.2f €", forecast.einnahmen))"
                einnahmenString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
                
                let ausgabenString = "Ausgaben: \(String(format: "%.2f €", forecast.ausgaben))"
                ausgabenString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 15
                
                let balanceString = "Kontostand: \(String(format: "%.2f €", forecast.balance))"
                balanceString.draw(at: CGPoint(x: 20, y: yOffset), withAttributes: textAttributes)
                yOffset += 25
            }
            
            // Diagramme
            if let incomeImage = incomeChartImage {
                let imageRect = CGRect(x: 20, y: yOffset, width: pageWidth - 40, height: 200)
                incomeImage.draw(in: imageRect)
                yOffset += 220
            }
            
            if let categoryImage = categoryChartImage {
                let imageRect = CGRect(x: 20, y: yOffset, width: pageWidth - 40, height: 200)
                categoryImage.draw(in: imageRect)
            }
        }
        
        return data
    }
}
