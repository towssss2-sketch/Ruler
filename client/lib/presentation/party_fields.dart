import 'package:flutter/material.dart';
import '../domain/case_detail.dart';

/// 每行独立控制器与稳定标识，删除相邻行不串位；仅驻留编辑页面内存。
class PartyFields {
  PartyFields(CaseParty party)
    : id = party.id,
      role = party.role,
      name = TextEditingController(text: party.name),
      phone = TextEditingController(text: party.phone),
      idCard = TextEditingController(text: party.idCard),
      address = TextEditingController(text: party.address);
  final key = UniqueKey();
  final String? id;
  String role;
  final TextEditingController name, phone, idCard, address;

  CaseParty get value => CaseParty(
    id: id,
    role: role,
    name: name.text.trim(),
    phone: _optional(phone),
    idCard: _optional(idCard),
    address: _optional(address),
  );
  String? _optional(TextEditingController field) =>
      field.text.trim().isEmpty ? null : field.text.trim();
  void dispose() {
    name.dispose();
    phone.dispose();
    idCard.dispose();
    address.dispose();
  }
}

class PartyFieldsCard extends StatelessWidget {
  const PartyFieldsCard({
    required this.fields,
    required this.index,
    required this.busy,
    required this.remove,
    super.key,
  });
  final PartyFields fields;
  final int index;
  final bool busy;
  final VoidCallback? remove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('当事人 ${index + 1}')),
              TextButton(
                onPressed: busy ? null : remove,
                child: const Text('移除此人'),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: fields.role,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '诉讼角色'),
            items: partyRoles.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) fields.role = value;
                  },
          ),
          _field(fields.name, '姓名（虚构）', 128),
          _field(fields.phone, '电话（可空）', 64),
          _field(fields.idCard, '证件号（可空）', 64),
          _field(fields.address, '地址（可空）', 1000),
        ],
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label, int limit) =>
      TextField(
        controller: controller,
        enabled: !busy,
        maxLength: limit,
        decoration: InputDecoration(labelText: label),
      );
}
