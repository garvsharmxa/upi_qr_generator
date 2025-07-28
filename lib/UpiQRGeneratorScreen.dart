import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

class UpiQRGeneratorScreen extends StatefulWidget {
  @override
  _UpiQRGeneratorScreenState createState() => _UpiQRGeneratorScreenState();
}

class _UpiQRGeneratorScreenState extends State<UpiQRGeneratorScreen>
    with TickerProviderStateMixin {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _upiIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String? _upiUrl;
  Timer? _qrCountdownTimer;
  Timer? _paymentStatusTimer;
  int _remainingSeconds = 0;
  bool _isQRExpired = false;
  String _paymentStatus = 'idle'; // idle, pending, success, failed, expired
  String _transactionId = '';
  String _paymentReference = '';
  String _actualTransactionId = '';
  Map<String, dynamic> _paymentDetails = {};
  List<Map<String, dynamic>> _transactionHistory = [];
  bool _isAdvancedMode = false;

  late AnimationController _pulseController;
  late AnimationController _successController;
  late AnimationController _scanController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successAnimation;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize default values
    _upiIdController.text = "6378339891@upi";
    _nameController.text = "Garv Sharma";

    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _successController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _scanController = AnimationController(
      duration: Duration(milliseconds: 3000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _successAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
  }

  void _generateQR() async {
    final amount = _amountController.text.trim();
    final upiId = _upiIdController.text.trim();
    final name = _nameController.text.trim();

    if (amount.isEmpty) {
      _showSnackBar("Please enter an amount", Colors.red);
      return;
    }

    if (double.tryParse(amount) == null || double.parse(amount) <= 0) {
      _showSnackBar("Please enter a valid amount", Colors.red);
      return;
    }

    if (upiId.isEmpty || !_isValidUpiId(upiId)) {
      _showSnackBar("Please enter a valid UPI ID", Colors.red);
      return;
    }

    if (name.isEmpty) {
      _showSnackBar("Please enter recipient name", Colors.red);
      return;
    }

    // Cancel previous timers
    _qrCountdownTimer?.cancel();
    _paymentStatusTimer?.cancel();

    // Generate unique transaction reference
    _transactionId = 'TXN${DateTime.now().millisecondsSinceEpoch}';
    _paymentReference = 'REF${Random().nextInt(999999).toString().padLeft(6, '0')}';

    final note = _noteController.text.trim().isEmpty
        ? "Payment using QR"
        : _noteController.text.trim();

    setState(() {
      _upiUrl = "upi://pay?pa=$upiId&pn=$name&tn=$note&am=$amount&cu=INR&tr=$_paymentReference";
      _isQRExpired = false;
      _remainingSeconds = 120; // 10 minutes
      _paymentStatus = 'pending';
      _paymentDetails = {
        'amount': amount,
        'upiId': upiId,
        'name': name,
        'note': note,
        'reference': _paymentReference,
        'generatedAt': DateTime.now().toIso8601String(),
      };
    });

    _startCountdown();
    _startPaymentStatusCheck();
    _scanController.forward();
    _showSnackBar("QR Code generated successfully!", Colors.green);
    HapticFeedback.lightImpact();
  }

  bool _isValidUpiId(String upiId) {
    final regex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
    return regex.hasMatch(upiId);
  }

  void _startCountdown() {
    _qrCountdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_remainingSeconds == 0) {
        timer.cancel();
        setState(() {
          _upiUrl = null;
          _isQRExpired = true;
          _paymentStatus = 'expired';
        });
        _paymentStatusTimer?.cancel();
        _addToHistory('expired');
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  void _startPaymentStatusCheck() {
    _paymentStatusTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      if (_paymentStatus == 'pending' && _remainingSeconds > 0) {
        await _checkPaymentStatus();
      }
    });
  }

  Future<void> _checkPaymentStatus() async {
    try {
      // Simulate API call to check payment status
      // In real implementation, this would call your backend API
      final response = await _mockPaymentStatusAPI();

      if (response['status'] == 'success') {
        _paymentStatusTimer?.cancel();
        _qrCountdownTimer?.cancel();
        setState(() {
          _paymentStatus = 'success';
          _actualTransactionId = response['transactionId'] ?? '';
          _paymentDetails['actualTransactionId'] = _actualTransactionId;
          _paymentDetails['completedAt'] = DateTime.now().toIso8601String();
        });

        _successController.forward();
        _addToHistory('success');
        _showSnackBar("Payment Successful! ✅", Colors.green);
        HapticFeedback.heavyImpact();

      } else if (response['status'] == 'failed') {
        _paymentStatusTimer?.cancel();
        _qrCountdownTimer?.cancel();
        setState(() {
          _paymentStatus = 'failed';
          _paymentDetails['failureReason'] = response['reason'] ?? 'Unknown error';
          _paymentDetails['failedAt'] = DateTime.now().toIso8601String();
        });

        _addToHistory('failed');
        _showSnackBar("Payment Failed! ❌", Colors.red);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      print('Error checking payment status: $e');
    }
  }

  Future<Map<String, dynamic>> _mockPaymentStatusAPI() async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500));

    // Simulate different scenarios based on time elapsed
    final elapsed = 600 - _remainingSeconds;

    if (elapsed > 30) { // After 30 seconds, simulate random completion
      final random = Random().nextInt(100);
      if (random < 25) { // 25% success rate
        return {
          'status': 'success',
          'transactionId': 'UPI${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(9999)}',
          'payerVpa': 'user@paytm',
          'amount': _paymentDetails['amount'],
          'timestamp': DateTime.now().toIso8601String(),
        };
      } else if (random < 30) { // 5% failure rate
        return {
          'status': 'failed',
          'reason': 'Insufficient balance',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
    }

    return {'status': 'pending'};
  }

  void _addToHistory(String status) {
    _transactionHistory.insert(0, {
      'transactionId': _transactionId,
      'paymentReference': _paymentReference,
      'actualTransactionId': _actualTransactionId,
      'amount': _paymentDetails['amount'],
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
      'upiId': _paymentDetails['upiId'],
      'name': _paymentDetails['name'],
    });

    // Keep only last 50 transactions
    if (_transactionHistory.length > 50) {
      _transactionHistory.removeLast();
    }
  }

  void _regenerateQR() {
    if (_amountController.text.trim().isNotEmpty) {
      _generateQR();
    } else {
      _showSnackBar("Please enter an amount first", Colors.orange);
    }
  }

  void _clearAll() {
    _qrCountdownTimer?.cancel();
    _paymentStatusTimer?.cancel();
    setState(() {
      _amountController.clear();
      _noteController.clear();
      _upiUrl = null;
      _isQRExpired = false;
      _paymentStatus = 'idle';
      _remainingSeconds = 0;
      _transactionId = '';
      _paymentReference = '';
      _actualTransactionId = '';
      _paymentDetails.clear();
    });
    _successController.reset();
    _scanController.reset();
  }

  void _copyTransactionDetails() {
    final details = '''
Transaction Details:
Amount: ₹${_paymentDetails['amount']}
Reference: $_paymentReference
${_actualTransactionId.isNotEmpty ? 'Transaction ID: $_actualTransactionId' : ''}
Status: ${_getStatusText()}
Generated: ${_formatDateTime(_paymentDetails['generatedAt'] ?? '')}
${_paymentStatus == 'success' ? 'Completed: ${_formatDateTime(_paymentDetails['completedAt'] ?? '')}' : ''}
''';

    Clipboard.setData(ClipboardData(text: details));
    _showSnackBar("Transaction details copied!", Colors.blue);
  }

  void _showTransactionHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "Transaction History",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: _transactionHistory.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      "No transactions yet",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _transactionHistory.length,
                itemBuilder: (context, index) {
                  final txn = _transactionHistory[index];
                  return _buildHistoryItem(txn);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> txn) {
    Color statusColor;
    IconData statusIcon;

    switch (txn['status']) {
      case 'success':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'expired':
        statusColor = Colors.grey;
        statusIcon = Icons.timer_off;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(statusIcon, color: statusColor),
        ),
        title: Text("₹${txn['amount']}", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("To: ${txn['name']} (${txn['upiId']})"),
            Text("Ref: ${txn['paymentReference']}"),
            if (txn['actualTransactionId']?.isNotEmpty == true)
              Text("TXN: ${txn['actualTransactionId']}",
                  style: TextStyle(fontSize: 12, color: Colors.blue)),
            Text(_formatDateTime(txn['timestamp']),
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            txn['status'].toUpperCase(),
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String isoString) {
    if (isoString.isEmpty) return '';
    final dateTime = DateTime.parse(isoString);
    return "${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
        action: message.contains("copied") ? null : SnackBarAction(
          label: "OK",
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  Color _getStatusColor() {
    switch (_paymentStatus) {
      case 'success': return Colors.green;
      case 'failed': return Colors.red;
      case 'expired': return Colors.grey;
      case 'pending': return Colors.orange;
      default: return Colors.blue;
    }
  }

  IconData _getStatusIcon() {
    switch (_paymentStatus) {
      case 'success': return Icons.check_circle;
      case 'failed': return Icons.error;
      case 'expired': return Icons.timer_off;
      case 'pending': return Icons.hourglass_empty;
      default: return Icons.qr_code;
    }
  }

  String _getStatusText() {
    switch (_paymentStatus) {
      case 'success': return 'Payment Successful';
      case 'failed': return 'Payment Failed';
      case 'expired': return 'QR Code Expired';
      case 'pending': return 'Waiting for Payment';
      default: return 'Ready to Generate QR';
    }
  }

  @override
  void dispose() {
    _qrCountdownTimer?.cancel();
    _paymentStatusTimer?.cancel();
    _amountController.dispose();
    _noteController.dispose();
    _upiIdController.dispose();
    _nameController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFFf093fb),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Header with actions
                Container(
                  margin: EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(Icons.qr_code_2, color: Colors.white, size: 28),
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "UPI QR Generator Pro",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              "Advanced payment tracking & history",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _showTransactionHistory,
                        icon: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.history, color: Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _isAdvancedMode = !_isAdvancedMode),
                        icon: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isAdvancedMode
                                ? Colors.white.withOpacity(0.3)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.settings, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: 15,
                  shadowColor: Colors.black.withOpacity(0.3),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: [Colors.white, Colors.grey.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        // Advanced Settings
                        if (_isAdvancedMode) ...[
                          _buildInputField(
                            controller: _upiIdController,
                            label: "UPI ID",
                            icon: Icons.account_balance,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          SizedBox(height: 16),
                          _buildInputField(
                            controller: _nameController,
                            label: "Recipient Name",
                            icon: Icons.person,
                            keyboardType: TextInputType.name,
                          ),
                          SizedBox(height: 16),
                        ],

                        // Basic Fields
                        _buildInputField(
                          controller: _amountController,
                          label: "Amount (INR)",
                          icon: Icons.currency_rupee,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                        ),
                        SizedBox(height: 16),
                        _buildInputField(
                          controller: _noteController,
                          label: "Note (Optional)",
                          icon: Icons.note_alt,
                          keyboardType: TextInputType.text,
                        ),
                        SizedBox(height: 24),

                        // Action Buttons
                        _buildActionButtons(),

                        // QR Code Display
                        if (_upiUrl != null) ...[
                          SizedBox(height: 30),
                          _buildQRSection(),
                        ] else if (_isQRExpired) ...[
                          SizedBox(height: 30),
                          _buildExpiredSection(),
                        ],

                        // Payment Status
                        if (_paymentStatus != 'idle') ...[
                          SizedBox(height: 20),
                          _buildPaymentStatus(),
                        ],

                        // Transaction Details
                        if (_paymentStatus == 'success' && _actualTransactionId.isNotEmpty) ...[
                          SizedBox(height: 16),
                          _buildTransactionDetails(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.deepPurple, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                onPressed: _generateQR,
                icon: Icons.qr_code,
                label: "Generate QR",
                color: Colors.deepPurple,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                onPressed: _upiUrl != null ? _regenerateQR : null,
                icon: Icons.refresh,
                label: "Regenerate",
                color: Colors.indigo,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                onPressed: _clearAll,
                icon: Icons.clear_all,
                label: "Clear All",
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                onPressed: _paymentDetails.isNotEmpty ? _copyTransactionDetails : null,
                icon: Icons.copy,
                label: "Copy Details",
                color: Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed != null ? color : Colors.grey,
        padding: EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
      ),
    );
  }

  Widget _buildQRSection() {
    return AnimatedBuilder(
      animation: _scanAnimation,
      builder: (context, child) {
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                "Scan using any UPI App",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
              SizedBox(height: 8),
              Text(
                "Payment Reference: $_paymentReference",
                style: TextStyle(fontSize: 12, color: Colors.blue.shade600, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              AnimatedBuilder(
                animation: _paymentStatus == 'pending' ? _pulseAnimation : _successAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _paymentStatus == 'pending' ? _pulseAnimation.value : 1.0,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _getStatusColor().withOpacity(0.3), width: 2),
                      ),
                      child: QrImageView(
                        data: _upiUrl!,
                        version: QrVersions.auto,
                        size: 220.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, color: Colors.red.shade600, size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Expires in ${_formatTime(_remainingSeconds)}",
                      style: TextStyle(fontSize: 13, color: Colors.red.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpiredSection() {
    return Container(
      padding: EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.timer_off, color: Colors.red.shade600, size: 60),
          SizedBox(height: 16),
          Text("QR Code has expired", style: TextStyle(color: Colors.red.shade600, fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text("Generate a new QR code to continue", style: TextStyle(color: Colors.red.shade400, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPaymentStatus() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _getStatusColor().withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _paymentStatus == 'success' ? _successAnimation : _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: _paymentStatus == 'success'
                    ? (0.8 + 0.4 * _successAnimation.value)
                    : (_paymentStatus == 'pending' ? _pulseAnimation.value : 1.0),
                child: Icon(_getStatusIcon(), color: _getStatusColor(), size: 24),
              );
            },
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(),
                  ),
                ),
                if (_paymentStatus == 'pending')
                  Text(
                    "Please complete payment in your UPI app",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                if (_paymentStatus == 'failed' && _paymentDetails['failureReason'] != null)
                  Text(
                    "Reason: ${_paymentDetails['failureReason']}",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionDetails() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.green.shade600, size: 20),
              SizedBox(width: 8),
              Text(
                "Transaction Completed",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildDetailRow("Amount", "₹${_paymentDetails['amount']}"),
          _buildDetailRow("Transaction ID", _actualTransactionId),
          _buildDetailRow("Payment Reference", _paymentReference),
          _buildDetailRow("Recipient", "${_paymentDetails['name']} (${_paymentDetails['upiId']})"),
          if (_paymentDetails['note']?.isNotEmpty == true)
            _buildDetailRow("Note", _paymentDetails['note']),
          _buildDetailRow("Completed At", _formatDateTime(_paymentDetails['completedAt'] ?? '')),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyTransactionDetails,
                  icon: Icon(Icons.copy, size: 16),
                  label: Text("Copy Details"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Share functionality could be added here
                    _showSnackBar("Share feature coming soon!", Colors.blue);
                  },
                  icon: Icon(Icons.share, size: 16),
                  label: Text("Share"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade600,
                    side: BorderSide(color: Colors.green.shade600),
                    padding: EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              "$label:",
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}