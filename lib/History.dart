import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryPage extends StatelessWidget {
  final String documentId;

  HistoryPage({required this.documentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('issp_documents').doc(documentId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Something went wrong: ${snapshot.error}'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('No data available.'));
          }

          // Extract the entire document data from the snapshot
          var data = snapshot.data!.data() as Map<String, dynamic>;

          // Create a list of all fields from the document
          List<Widget> documentFields = [];

          data.forEach((key, value) {
            // Check if the value is a nested map (i.e., sections), and handle it accordingly
            if (value is Map) {
              // If it's a nested map, iterate over its contents (like "sections")
              documentFields.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '$key:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              );
              value.forEach((sectionKey, sectionValue) {
                documentFields.add(
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$sectionKey:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        Text('Last Modified: ${sectionValue['lastModified']}', style: TextStyle(fontSize: 14)),
                        Text('Status: ${sectionValue['status']}', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                );
              });
            } else {
              // If it's a simple field, just display it
              documentFields.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    '$key: $value',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              );
            }
          });

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: documentFields,  // Display the dynamically generated fields
            ),
          );
        },
      ),
    );
  }
}
