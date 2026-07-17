import 'package:flutter/material.dart';
import 'chat_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

final supabase = Supabase.instance.client;

class ProfileScreen extends StatefulWidget {
  final String? userId;
  final String name;
  final bool isCurrentUser;

  const ProfileScreen({
    super.key,
    this.userId,
    this.name = "", // Placeholder removed
    this.isCurrentUser = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  bool _isLoading = true;
  bool _isEditing = false;

  // Controllers initialized immediately to prevent LateInitializationError
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _skillInputController = TextEditingController();

  List<String> _skillsList = [];
  User? get _authUser => supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _skillInputController.dispose();
    super.dispose();
  }

  // --- DATABASE LOGIC ---

  Future<void> _loadProfileData() async {
    final targetUid = widget.isCurrentUser ? _authUser?.id : widget.userId;

    if (targetUid != null) {
      try {
        final data = await supabase
            .from('profiles')
            .select()
            .eq('id', targetUid)
            .single();

        if (mounted) {
          setState(() {
            userData = data;
            // This fills the text box so it isn't empty when you hit 'Edit'
            _nameController.text = data['full_name']?.toString() ?? "";
            _bioController.text = data['bio']?.toString() ?? "";
            final lat = data['latitude'];
            final lng = data['longitude'];
            _latController.text =
                lat != null ? lat.toString() : "";
            _lngController.text =
                lng != null ? lng.toString() : "";
            _skillsList = List<String>.from(data['skills'] ?? []);
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint("Error fetching profile: $e");
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addSkill(String skill) {
    if (skill.trim().isNotEmpty && !_skillsList.contains(skill.trim())) {
      setState(() {
        _skillsList.add(skill.trim());
        _skillInputController.clear();
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_authUser == null) return;
    setState(() => _isLoading = true);
    try {
      // Updates Supabase profile row keyed by auth user id
      await supabase.from('profiles').update({
        'full_name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'skills': _skillsList,
        'latitude': double.tryParse(_latController.text.trim()),
        'longitude': double.tryParse(_lngController.text.trim()),
      }).eq('id', _authUser!.id);

      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Profile updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Failed to save"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    // 1. Pick the image
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300, // Keep file size small
      imageQuality: 80,
    );

    if (image == null) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      // Read bytes (works on web + mobile)
      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last.toLowerCase();
      final fileName = '${_authUser!.id}.$fileExt';

      // 2. Upload to Supabase Storage (include contentType)
      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            bytes,
            fileOptions:
                FileOptions(upsert: true, contentType: 'image/$fileExt'),
          );

      // 3. Get the Public URL
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // 4. Update the profile table
      await supabase.from('profiles').update({
        'avatar_url': imageUrl,
      }).eq('id', _authUser!.id);

      // Refresh the local data to show the new image
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Photo updated!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    // Global loading shield
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final displayName = (userData?['full_name'] != null &&
            userData?['full_name'].toString().isNotEmpty == true)
        ? userData!['full_name'].toString()
        : (_nameController.text.isNotEmpty
            ? _nameController.text
            : "New Member");
    final rating = (userData?['rating'] ?? 5.0).toString();
    final helps = (userData?['helps_count'] ?? 0).toString();
    final karma = (userData?['karma_points'] ?? 0).toString();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          widget.isCurrentUser ? 'My Profile' : "$displayName's Profile",
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        elevation: 0.5,
        actions: widget.isCurrentUser
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh stats',
                  onPressed: () {
                    setState(() => _isLoading = true);
                    _loadProfileData();
                  },
                ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.check : Icons.edit),
                  onPressed: () => _isEditing
                      ? _saveProfile()
                      : setState(() => _isEditing = true),
                ),
              ]
            : [],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Profile Card
            Container(
              color: scheme.surfaceContainerLowest,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              width: double.infinity,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isEditing ? _uploadAvatar : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: (userData?['avatar_url'] != null &&
                                  userData!['avatar_url'].toString().isNotEmpty)
                              ? NetworkImage(userData!['avatar_url'].toString())
                              : null,
                          child: (userData?['avatar_url'] == null)
                              ? const Icon(Icons.person,
                                  size: 50, color: Colors.grey)
                              : null,
                        ),
                        if (_isEditing)
                          const Positioned(
                            bottom: 0,
                            right: 0,
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFF2167FF),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.camera_alt,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  _isEditing
                      ? TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                              labelText: "Full Name",
                              border: OutlineInputBorder()),
                          textAlign: TextAlign.center,
                        )
                      : Text(displayName,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text("Verified RapidAid Member ✅",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 10),
            _buildSectionLabel("Bio"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isEditing
                  ? TextFormField(
                      controller: _bioController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "Tell us about yourself..."),
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_bioController.text.isEmpty
                          ? "No bio yet."
                          : _bioController.text),
                    ),
            ),

            const SizedBox(height: 16),
            _buildSectionLabel("Map location (latitude / longitude)"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isEditing
                  ? Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              labelText: "Latitude",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _lngController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              labelText: "Longitude",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      (_latController.text.isEmpty || _lngController.text.isEmpty)
                          ? "Not set — add coordinates in Edit for live tracking."
                          : "${_latController.text}, ${_lngController.text}",
                      style: const TextStyle(color: Colors.black54),
                    ),
            ),

            const SizedBox(height: 20),
            // Statistics Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStatCard(rating, "Rating", Icons.star, Colors.orange),
                  const SizedBox(width: 10),
                  _buildStatCard(helps, "Helps", Icons.volunteer_activism,
                      Colors.redAccent),
                  const SizedBox(width: 10),
                  _buildStatCard(karma, "Karma", Icons.bolt, Colors.blue),
                ],
              ),
            ),

            const SizedBox(height: 25),
            _buildSectionLabel("Skills & Resources"),

            // Interactive Skill Input
            if (_isEditing)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _skillInputController,
                  decoration: InputDecoration(
                    hintText: "Add skill (e.g. Mechanic, Driving)",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _addSkill(_skillInputController.text)),
                  ),
                  onSubmitted: (val) => _addSkill(val),
                ),
              ),

            // Skills Display (Chips)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: _skillsList
                    .map((skill) => Chip(
                          label: Text(skill),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
                          onDeleted: _isEditing
                              ? () => setState(() => _skillsList.remove(skill))
                              : null,
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 40),
            // Message or Logout Buttons
            if (!widget.isCurrentUser) _buildMessageButton(displayName),
            if (widget.isCurrentUser) _buildLogoutButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- HELPER UI METHODS ---

  Widget _buildStatCard(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10),
      child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ))),
    );
  }

  Widget _buildMessageButton(String displayName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailsScreen(
                peerName: displayName,
                peerUserId: widget.userId ?? '',
              ),
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text('Message $displayName'),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextButton.icon(
        onPressed: () async {
          final navigator = Navigator.of(context);
          await supabase.auth.signOut();
          navigator.popUntil((route) => route.isFirst);
        },
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text("Logout",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
