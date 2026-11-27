namespace SapBulkChange.Models;

public sealed record AcdocaLine(string Belnr, string Gjahr, string Item, string Racct,
    string CurrentAssignment, string DocumentType, DateOnly? PostingDate);
