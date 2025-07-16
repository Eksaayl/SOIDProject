import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'utils/dialog_utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _divisionController = TextEditingController();
  Uint8List? _pickedImage;
  String _currentUsername = '';
  String _currentDivision = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _divisionController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final data = userDoc.data()!;
          setState(() {
            _currentUsername = data['username'] ?? '';
            _currentDivision = data['service'] ?? '';
            _usernameController.text = _currentUsername;
            _divisionController.text = _currentDivision;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load user data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _pickedImage = bytes;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveProfilePicture() async {
    if (_pickedImage == null) return;

    final confirm = await DialogUtils.showSaveConfirmationDialog(
      context: context,
      title: 'Save Profile Picture',
      message: 'Are you sure you want to update your profile picture?',
      confirmText: 'Save',
      cancelText: 'Cancel',
    );
    if (confirm != true) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_photos')
            .child('${user.uid}.jpg');
        
        // Upload the image bytes
        final uploadTask = storageRef.putData(_pickedImage!);
        final snapshot = await uploadTask;
        
        // Get the download URL
        final downloadURL = await snapshot.ref.getDownloadURL();
        
        // Update user document with profile picture URL
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'profilePictureURL': downloadURL});

        // Close loading dialog
        Navigator.of(context).pop();

        // Clear the picked image
        setState(() {
          _pickedImage = null;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload profile picture: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty')),
      );
      return;
    }

    if (newUsername == _currentUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username is already set to this value')),
      );
      return;
    }

    final confirm = await DialogUtils.showSaveConfirmationDialog(
      context: context,
      title: 'Save Username Change',
      message: 'Are you sure you want to change your username to "$newUsername"?',
      confirmText: 'Save',
      cancelText: 'Cancel',
    );
    if (confirm != true) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({'username': newUsername});
        setState(() {
          _currentUsername = newUsername;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username updated successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update username: $e')),
      );
    }
  }

  Future<void> _updateDivision() async {
    final newDivision = _divisionController.text.trim();
    if (newDivision.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Division/Service cannot be empty')),
      );
      return;
    }

    if (newDivision == _currentDivision) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Division/Service is already set to this value')),
      );
      return;
    }

    final confirm = await DialogUtils.showSaveConfirmationDialog(
      context: context,
      title: 'Save Division/Service Change',
      message: 'Are you sure you want to change your division/service to "$newDivision"?',
      confirmText: 'Save',
      cancelText: 'Cancel',
    );
    if (confirm != true) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({'service': newDivision});
        setState(() {
          _currentDivision = newDivision;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Division/Service updated successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update division/service: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 32,  
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: false, 
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            const Text(
              'Manage your profile information and settings.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 24), 

            // Change Profile Picture Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Profile Picture',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _pickedImage != null 
                            ? MemoryImage(_pickedImage!) 
                            : null,
                        child: _pickedImage == null 
                            ? Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.grey[600],
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Profile Picture',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _pickedImage != null 
                                  ? 'New image selected - click Save Changes to upload'
                                  : 'Upload a new profile picture',
                              style: TextStyle(
                                fontSize: 14,
                                color: _pickedImage != null ? Colors.green[600] : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.camera_alt, color: Colors.white),
                          label: const Text(
                            'Take Photo',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff021e84),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                      if (_pickedImage != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveProfilePicture,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text(
                              'Save Changes',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff021e84),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Change Username Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Username',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: $_currentUsername',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'New Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateUsername,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff021e84),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text(
                      'Change Username',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Change Division/Service Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Division/Service',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: $_currentDivision',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _divisionController,
                    decoration: const InputDecoration(
                      labelText: 'New Division/Service',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _updateDivision,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff021e84),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    child: const Text(
                      'Change Division/Service',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 