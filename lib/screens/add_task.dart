import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


class AddTaskPage extends StatefulWidget {
  @override
  _AddTaskPageState createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _titleController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _descController = TextEditingController();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => _selectedDate = d);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) {
    return showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        _selectedDate == null ? '' : DateFormat.yMMMEd().format(_selectedDate!);
    final startText =
        _startTime == null ? '-- : --' : _startTime!.format(context);
    final endText = _endTime == null ? '-- : --' : _endTime!.format(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text('Add Task', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        leading: BackButton(color: Colors.black),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white)),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Title
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Title',
                      style: TextStyle(fontWeight: FontWeight.w500))),
              SizedBox(height: 6),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Add new plot',
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),

              SizedBox(height: 16),
              // Date
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Date',
                      style: TextStyle(fontWeight: FontWeight.w500))),
              SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dateText.isEmpty ? '' : dateText,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              SizedBox(height: 16),
              // Start & End times
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start time',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final t = await _pickTime(_startTime);
                            if (t != null) setState(() => _startTime = t);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child:
                                Text(startText, style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('End Time',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final t = await _pickTime(_endTime);
                            if (t != null) setState(() => _endTime = t);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child:
                                Text(endText, style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),
              // Description
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Description',
                      style: TextStyle(fontWeight: FontWeight.w500))),
              SizedBox(height: 6),
              TextField(
                controller: _descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Add more task details here...',
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              Spacer(),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Return new task
                    if (_titleController.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'title': _titleController.text.trim(),
                      'time': '${startText} – ${endText}',
                      'status': 'Not started',
                      'checked': false,
                      'description': _descController.text.trim(),
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
