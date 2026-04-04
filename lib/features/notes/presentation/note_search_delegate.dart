import 'package:flutter/material.dart';

import '../domain/note.dart';

class NoteSearchDelegate extends SearchDelegate<Note?> {
  NoteSearchDelegate({
    required Future<List<Note>> Function(String query) searchNotes,
  }) : _searchNotes = searchNotes;

  final Future<List<Note>> Function(String query) _searchNotes;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () {
            query = '';
          },
          icon: const Icon(Icons.clear),
          tooltip: 'Clear',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back',
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResults(
      query: query,
      searchNotes: _searchNotes,
      onSelected: (note) => close(context, note),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchResults(
      query: query,
      searchNotes: _searchNotes,
      onSelected: (note) => close(context, note),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.searchNotes,
    required this.onSelected,
  });

  final String query;
  final Future<List<Note>> Function(String query) searchNotes;
  final ValueChanged<Note> onSelected;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return const Center(
        child: Text('Search notes by title or content.'),
      );
    }

    return FutureBuilder<List<Note>>(
      future: searchNotes(trimmedQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final notes = snapshot.data ?? const <Note>[];
        if (notes.isEmpty) {
          return const Center(
            child: Text('No matching notes found.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final note = notes[index];
            final title = note.title.isEmpty ? 'Untitled note' : note.title;
            final preview = note.content.trim().isEmpty
                ? 'No content'
                : note.content.trim().replaceAll('\n', ' ');

            return Card(
              child: ListTile(
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(note),
              ),
            );
          },
        );
      },
    );
  }
}
