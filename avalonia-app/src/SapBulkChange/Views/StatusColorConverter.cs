using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;
using SapBulkChange.Models;

namespace SapBulkChange.Views;

public sealed class StatusColorConverter : IValueConverter
{
    private static readonly IBrush BlueBrush = new SolidColorBrush(Color.Parse("#1D4ED8"));
    private static readonly IBrush GrayBrush = new SolidColorBrush(Color.Parse("#6B7280"));
    private static readonly IBrush OrangeBrush = new SolidColorBrush(Color.Parse("#D97706"));
    private static readonly IBrush TealBrush = new SolidColorBrush(Color.Parse("#0D9488"));
    private static readonly IBrush GreenBrush = new SolidColorBrush(Color.Parse("#15803D"));
    private static readonly IBrush RedBrush = new SolidColorBrush(Color.Parse("#DC2626"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not LineStatus status)
            return GrayBrush;

        return status switch
        {
            LineStatus.PLANNED => BlueBrush,
            LineStatus.SKIPPED_ALREADY_SET => GrayBrush,
            LineStatus.DOC_NOT_FOUND or LineStatus.NO_MATCH or LineStatus.AMBIGUOUS => OrangeBrush,
            LineStatus.SENT => TealBrush,
            LineStatus.CHANGED => GreenBrush,
            LineStatus.NOT_CHANGED => OrangeBrush,
            LineStatus.XSD_INVALID or LineStatus.SEND_ERROR or LineStatus.VERIFY_ERROR => RedBrush,
            _ => GrayBrush
        };
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public sealed class EnvBannerBrushConverter : IValueConverter
{
    private static readonly IBrush QasBrush = new SolidColorBrush(Color.Parse("#FEF3C7"));
    private static readonly IBrush PrdBrush = new SolidColorBrush(Color.Parse("#FEE2E2"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? PrdBrush : QasBrush;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}

public sealed class EnvTextBrushConverter : IValueConverter
{
    private static readonly IBrush QasText = new SolidColorBrush(Color.Parse("#92400E"));
    private static readonly IBrush PrdText = new SolidColorBrush(Color.Parse("#991B1B"));

    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? PrdText : QasText;

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
