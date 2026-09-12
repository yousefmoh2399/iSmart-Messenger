class PurchaseRequest {
  final String id;
  final String purchaseRequestNo;
  final String requestType;
  final String requestedBy;
  final String departmentId;
  final String status;
  final String priority;

  PurchaseRequest({
    required this.id,
    required this.purchaseRequestNo,
    required this.requestType,
    required this.requestedBy,
    required this.departmentId,
    required this.status,
    required this.priority,
  });

  factory PurchaseRequest.fromJson(Map<String, dynamic> json) {
    return PurchaseRequest(
      id: json['_id'] ?? '',
      purchaseRequestNo: json['purchaseRequestNo'] ?? '',
      requestType: json['requestType'] ?? '',
      requestedBy: json['requestedBy'] ?? '',
      departmentId: json['departmentId'] ?? '',
      status: json['status'] ?? '',
      priority: json['priority'] ?? '',
    );
  }
}
