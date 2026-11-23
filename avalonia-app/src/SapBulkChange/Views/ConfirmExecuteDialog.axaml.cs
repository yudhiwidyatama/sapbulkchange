using Avalonia.Controls;
using SapBulkChange.ViewModels;

namespace SapBulkChange.Views;

public partial class ConfirmExecuteDialog : Window
{
    public ConfirmExecuteDialog()
    {
        InitializeComponent();
    }

    public ConfirmExecuteDialog(ConfirmExecuteViewModel viewModel) : this()
    {
        DataContext = viewModel;
        viewModel.CloseRequested += result => Close(result);
    }
}
