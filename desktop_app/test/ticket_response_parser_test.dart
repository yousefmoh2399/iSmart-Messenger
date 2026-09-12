import 'package:desktop_app/features/tickets/data/ticket_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges response data over legacy root fields', () {
    final merged = mergeResponseBody({
      'success': true,
      'title': 'legacy',
      'data': {'title': 'current', 'ticketNumber': 'IT-1'},
    });

    expect(merged, {'title': 'current', 'ticketNumber': 'IT-1'});
    expect(
      readMeta({
        'meta': {'page': 2},
      }),
      {'page': 2},
    );
  });

  test('reads and normalizes tickets from common response envelopes', () {
    expect(
      readTicketMap({
        'data': {
          'ticket': {'_id': 'ticket-1', 'title': 'Printer issue'},
        },
      }),
      {'_id': 'ticket-1', 'id': 'ticket-1', 'title': 'Printer issue'},
    );
    expect(readTicketMap({'_id': 'ticket-2', 'ticketNumber': 'IT-2'}), {
      '_id': 'ticket-2',
      'id': 'ticket-2',
      'ticketNumber': 'IT-2',
    });
    expect(readTicketMap({'success': true}), isEmpty);
  });

  test('filters malformed ticket list entries', () {
    final tickets = readTicketsList({
      'data': [
        {'_id': 'ticket-1'},
        {'title': 'No id yet'},
        {'ignored': true},
        'invalid',
      ],
    });

    expect(tickets, [
      {'_id': 'ticket-1', 'id': 'ticket-1'},
      {'title': 'No id yet'},
    ]);
  });

  test('normalizes updates and fills the creator name', () {
    final updates = readUpdatesList({
      'updates': [
        {
          '_id': 'update-1',
          'kind': 'comment',
          'createdBy': {'fullName': ''},
          'createdByName': 'Yousef',
        },
        {'ignored': true},
      ],
    });

    expect(updates.single['id'], 'update-1');
    expect(updates.single['createdBy'], {'fullName': 'Yousef'});
  });

  test('reads arbitrary objects and object lists', () {
    expect(
      readObject({
        'data': {
          'settings': {'enabled': true},
        },
      }, 'settings'),
      {'enabled': true},
    );
    expect(
      readObjectList({
        'data': {
          'members': [
            {'id': 'user-1'},
            null,
          ],
        },
      }, 'members'),
      [
        {'id': 'user-1'},
      ],
    );
  });
}
