import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/player.dart';
import '../providers/match_provider.dart';
import 'match_screen.dart';

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({Key? key}) : super(key: key);

  @override
  _CreateMatchScreenState createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _matchNameController = TextEditingController();
  final TextEditingController _teamANameController = TextEditingController();
  final TextEditingController _teamBNameController = TextEditingController();

  int _selectedPlayers = 11;
  final List<int> _playerOptions = [3, 5, 6, 7, 9, 11];

  // Lists to hold player data. For simplicity, we just generate default names initially
  List<Player> _teamAPlayers = [];
  List<Player> _teamBPlayers = [];

  @override
  void initState() {
    super.initState();
    _updatePlayerLists();
  }

  void _updatePlayerLists() {
    _teamAPlayers = List.generate(
      _selectedPlayers,
      (i) => Player(id: "A$i", name: "Player A${i+1}")
    );
    _teamBPlayers = List.generate(
      _selectedPlayers,
      (i) => Player(id: "B$i", name: "Player B${i+1}")
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Create Match", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Match Details"),
              TextFormField(
                controller: _matchNameController,
                decoration: _inputDecoration("Match Name"),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _teamANameController,
                      decoration: _inputDecoration("Team A Name"),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _teamBNameController,
                      decoration: _inputDecoration("Team B Name"),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSectionTitle("Players Per Team"),
              SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _playerOptions.length,
                  separatorBuilder: (_,__) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final count = _playerOptions[index];
                    final isSelected = count == _selectedPlayers;
                    return ChoiceChip(
                      label: Text("$count"),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedPlayers = count;
                            _updatePlayerLists();
                          });
                        }
                      },
                      selectedColor: Colors.black,
                      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle("Customize Players (Team A)"),
              ..._teamAPlayers.asMap().entries.map((entry) => _buildPlayerInput(entry.value, entry.key)).toList(),
              const SizedBox(height: 16),
               _buildSectionTitle("Customize Players (Team B)"),
              ..._teamBPlayers.asMap().entries.map((entry) => _buildPlayerInput(entry.value, entry.key)).toList(),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _startMatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text("Start Match", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  Widget _buildPlayerInput(Player player, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text("${index + 1}.", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: player.name,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
              onChanged: (v) => player.name = v,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<PlayerRole>(
            value: player.role,
            underline: Container(),
            onChanged: (PlayerRole? newValue) {
              setState(() {
                player.role = newValue!;
              });
            },
            items: PlayerRole.values.map<DropdownMenuItem<PlayerRole>>((PlayerRole value) {
              return DropdownMenuItem<PlayerRole>(
                value: value,
                child: Text(value.toString().split('.').last[0].toUpperCase()),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _startMatch() {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<MatchProvider>(context, listen: false);
      provider.initMatch(
        _matchNameController.text,
        _selectedPlayers,
        _teamANameController.text,
        _teamBNameController.text,
        _teamAPlayers,
        _teamBPlayers,
      );

      // Auto start for simplicity - Assume Team A bats first with first 2 players
      provider.startMatch(
        provider.teamA!, // Batting
        provider.teamB!, // Bowling
        provider.teamA!.players[0], // Striker
        provider.teamA!.players[1], // Non Striker
        provider.teamB!.players[0], // Bowler
      );

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MatchScreen()));
    }
  }
}
