using System.Diagnostics;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Platform.Storage;
using SapBulkChange.ViewModels;

namespace SapBulkChange.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        AddHandler(DragDrop.DropEvent, OnFileDrop);
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (DataContext is not MainWindowViewModel vm)
            return;

        vm.BrowseExcelRequested = async () =>
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Select SAP Assignment Excel File",
                AllowMultiple = false,
                FileTypeFilter =
                [
                    new FilePickerFileType("Excel Workbook") { Patterns = ["*.xlsx"] }
                ]
            });

            return files.FirstOrDefault()?.TryGetLocalPath();
        };

        vm.SaveCsvRequested = async () =>
        {
            var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
            {
                Title = "Export Assignment Change Results",
                SuggestedFileName = $"assignment_change_results_{DateTime.Now:yyyyMMdd_HHmmss}.csv",
                DefaultExtension = "csv",
                FileTypeChoices =
                [
                    new FilePickerFileType("CSV File") { Patterns = ["*.csv"] }
                ]
            });

            return file?.TryGetLocalPath();
        };

        vm.ConfirmExecuteRequested = async req =>
        {
            var dialogVm = new ConfirmExecuteViewModel(req);
            var dialog = new ConfirmExecuteDialog(dialogVm);
            return await dialog.ShowDialog<bool>(this);
        };

        vm.OpenFolderRequested = folderPath =>
        {
            try
            {
                if (!Directory.Exists(folderPath))
                    Directory.CreateDirectory(folderPath);

                Process.Start(new ProcessStartInfo
                {
                    FileName = folderPath,
                    UseShellExecute = true
                });
            }
            catch
            {
                // Ignore if OS shell cannot open folder
            }
        };
    }

    private static void OnDragOver(object? sender, DragEventArgs e)
    {
        e.DragEffects = e.Data.Contains(DataFormats.Files)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private void OnFileDrop(object? sender, DragEventArgs e)
    {
        if (DataContext is not MainWindowViewModel vm || vm.IsBusy)
            return;

        var files = e.Data.GetFiles();
        var xlsx = files?
            .Select(f => f.TryGetLocalPath())
            .FirstOrDefault(p => !string.IsNullOrWhiteSpace(p) &&
                                 p.EndsWith(".xlsx", StringComparison.OrdinalIgnoreCase));

        if (!string.IsNullOrWhiteSpace(xlsx))
            vm.LoadExcelFile(xlsx);
    }
}
