import 'api_client.dart';

class PollRepository {
  PollRepository(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>?> getPoll(String postId) async {
    try {
      return await _client.getJson('/api/v1/posts/$postId/poll');
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.notFound) return null;
      rethrow;
    }
  }

  Future<void> vote({
    required String pollId,
    required List<String> optionIds,
  }) async {
    await _client.putJson(
      '/api/v1/polls/$pollId/vote',
      body: {'option_ids': optionIds},
    );
  }
}
