package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jung-kurt/gofpdf"
)

const documentsStorageDir = "./storage/documents"

type DocumentService struct {
	docRepo      *repository.DocumentRepository
	orderRepo    *repository.OrderRepository
	userRepo     *repository.UserRepository
	shipmentRepo *repository.ShipmentRepository
}

func NewDocumentService(docRepo *repository.DocumentRepository, orderRepo *repository.OrderRepository, userRepo *repository.UserRepository, shipmentRepo *repository.ShipmentRepository) *DocumentService {
	return &DocumentService{docRepo: docRepo, orderRepo: orderRepo, userRepo: userRepo, shipmentRepo: shipmentRepo}
}

// Generate — renders the requested trade document as a PDF from the order's data and
// stores it under /storage/documents, served statically at /files/documents/<name>.
// Importer/exporter can generate any type; the assigned logistics partner can additionally
// generate the shipment-related documents (bill of lading, air waybill, shipping invoice).
func (s *DocumentService) Generate(ctx context.Context, orderID string, docType models.DocumentType, generatedBy string) (*models.Document, error) {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}

	authorized := generatedBy == order.ImporterID || generatedBy == order.ExporterID
	if !authorized && (docType == models.DocBillOfLading || docType == models.DocAirWaybill || docType == models.DocShippingInvoice) {
		shipment, shipErr := s.shipmentRepo.GetByOrderID(ctx, orderID)
		if shipErr == nil && shipment != nil && shipment.LogisticsID != nil && *shipment.LogisticsID == generatedBy {
			authorized = true
		}
	}
	if !authorized {
		return nil, fmt.Errorf("not authorized to generate documents for this order")
	}
	importer, err := s.userRepo.GetByID(ctx, order.ImporterID)
	if err != nil {
		return nil, err
	}
	exporter, err := s.userRepo.GetByID(ctx, order.ExporterID)
	if err != nil {
		return nil, err
	}

	if err := os.MkdirAll(documentsStorageDir, 0o755); err != nil {
		return nil, fmt.Errorf("prepare storage dir: %w", err)
	}

	fileName := fmt.Sprintf("%s_%s.pdf", order.OrderNumber, docType)
	filePath := filepath.Join(documentsStorageDir, fileName)

	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.AddPage()
	renderDocument(pdf, docType, order, importer, exporter)

	if err := pdf.OutputFileAndClose(filePath); err != nil {
		return nil, fmt.Errorf("write pdf: %w", err)
	}

	doc := &models.Document{
		OrderID:     order.ID,
		Type:        docType,
		FileURL:     "/files/documents/" + fileName,
		GeneratedBy: generatedBy,
	}
	if err := s.docRepo.Upsert(ctx, doc); err != nil {
		return nil, fmt.Errorf("save document record: %w", err)
	}
	return doc, nil
}

func (s *DocumentService) ListForOrder(ctx context.Context, orderID string) ([]models.Document, error) {
	return s.docRepo.ListByOrder(ctx, orderID)
}

func renderDocument(pdf *gofpdf.Fpdf, docType models.DocumentType, order *models.Order, importer, exporter *models.User) {
	pdf.SetFont("Arial", "B", 16)
	pdf.Cell(0, 10, documentTitle(docType))
	pdf.Ln(14)

	pdf.SetFont("Arial", "", 11)
	pdf.CellFormat(0, 7, fmt.Sprintf("Order Number: %s", order.OrderNumber), "", 1, "L", false, 0, "")
	pdf.CellFormat(0, 7, fmt.Sprintf("Date: %s", order.CreatedAt.Format("02-Jan-2006")), "", 1, "L", false, 0, "")
	pdf.Ln(4)

	pdf.SetFont("Arial", "B", 12)
	pdf.CellFormat(0, 7, "Exporter", "", 1, "L", false, 0, "")
	pdf.SetFont("Arial", "", 11)
	pdf.CellFormat(0, 6, exporter.FullName, "", 1, "L", false, 0, "")
	if exporter.CompanyName != nil {
		pdf.CellFormat(0, 6, *exporter.CompanyName, "", 1, "L", false, 0, "")
	}
	pdf.Ln(4)

	pdf.SetFont("Arial", "B", 12)
	pdf.CellFormat(0, 7, "Importer / Consignee", "", 1, "L", false, 0, "")
	pdf.SetFont("Arial", "", 11)
	pdf.CellFormat(0, 6, importer.FullName, "", 1, "L", false, 0, "")
	if importer.CompanyName != nil {
		pdf.CellFormat(0, 6, *importer.CompanyName, "", 1, "L", false, 0, "")
	}
	if order.DeliveryAddress != nil {
		pdf.MultiCell(0, 6, *order.DeliveryAddress, "", "L", false)
	}
	pdf.Ln(6)

	pdf.SetFont("Arial", "B", 11)
	pdf.CellFormat(70, 8, "Description", "1", 0, "L", false, 0, "")
	pdf.CellFormat(30, 8, "HSN Code", "1", 0, "C", false, 0, "")
	pdf.CellFormat(30, 8, "Quantity", "1", 0, "C", false, 0, "")
	pdf.CellFormat(30, 8, "Unit Price", "1", 0, "C", false, 0, "")
	pdf.CellFormat(30, 8, "Amount", "1", 1, "C", false, 0, "")

	pdf.SetFont("Arial", "", 11)
	hsn := ""
	if order.HSNCode != nil {
		hsn = *order.HSNCode
	}
	pdf.CellFormat(70, 8, order.ProductName, "1", 0, "L", false, 0, "")
	pdf.CellFormat(30, 8, hsn, "1", 0, "C", false, 0, "")
	pdf.CellFormat(30, 8, fmt.Sprintf("%.2f %s", order.Quantity, order.Unit), "1", 0, "C", false, 0, "")
	pdf.CellFormat(30, 8, fmt.Sprintf("%.2f", order.UnitPrice), "1", 0, "R", false, 0, "")
	pdf.CellFormat(30, 8, fmt.Sprintf("%.2f", order.TotalAmount), "1", 1, "R", false, 0, "")

	pdf.Ln(6)
	pdf.SetFont("Arial", "B", 11)
	pdf.CellFormat(0, 7, fmt.Sprintf("Total: %s %.2f", order.Currency, order.TotalAmount), "", 1, "R", false, 0, "")

	if docType == models.DocCertificateOfOrigin {
		pdf.Ln(10)
		pdf.SetFont("Arial", "", 11)
		pdf.MultiCell(0, 6, "It is hereby certified that the goods described above originate in India, in accordance with the applicable rules of origin.", "", "L", false)
	}

	pdf.Ln(20)
	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(0, 6, "Generated by One Bharat Export Import platform. This document is issued electronically.", "", 1, "L", false, 0, "")
}

func documentTitle(t models.DocumentType) string {
	switch t {
	case models.DocCommercialInvoice:
		return "Commercial Invoice"
	case models.DocPackingList:
		return "Packing List"
	case models.DocCertificateOfOrigin:
		return "Certificate of Origin"
	case models.DocBillOfLading:
		return "Bill of Lading"
	case models.DocAirWaybill:
		return "Air Waybill"
	case models.DocShippingInvoice:
		return "Shipping Invoice"
	default:
		return "Trade Document"
	}
}
