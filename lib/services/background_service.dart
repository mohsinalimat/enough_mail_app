import 'dart:math';

import 'package:background_fetch/background_fetch.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail_app/models/background_update_info.dart';
import 'package:enough_mail_app/services/notification_service.dart';
import 'package:enough_serialization/enough_serialization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../locator.dart';
import 'mail_service.dart';

class BackgroundService {
  static const String _keyInboxUids = 'nextUidsInfo';

  Future init() async {
    await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15,
          startOnBoot: true,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          requiredNetworkType: NetworkType.ANY,
        ), (String taskId) async {
      try {
        await locator<MailService>().resume();
      } catch (e, s) {
        print('Error: Unable to finish foreground background fetch: $e $s');
      }
      BackgroundFetch.finish(taskId);
    }, (String taskId) {
      BackgroundFetch.finish(taskId);
    });
    await BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
  }

  static void backgroundFetchHeadlessTask(HeadlessTask task) async {
    final taskId = task.taskId;
    print(
        'backgroundFetchHeadlessTask with taskId $taskId, timeout=${task.timeout}');
    if (task.timeout) {
      BackgroundFetch.finish(taskId);
      return;
    }
    try {
      await checkForNewMail();
    } catch (e, s) {
      print('Error during backgroundFetchHeadlessTask $e $s');
    } finally {
      BackgroundFetch.finish(taskId);
    }
  }

  Future saveStateOnPause() async {
    final mailClients = locator<MailService>().getMailClients();
    final futures = <Future>[];
    final info = BackgroundUpdateInfo();
    for (final client in mailClients) {
      futures.add(addNextUidFor(client, info));
    }
    await Future.wait(futures);
    final stringValue = Serializer().serialize(info);
    print('nextUids: $stringValue');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInboxUids, stringValue);
  }

  Future<void> addNextUidFor(
      final MailClient mailClient, final BackgroundUpdateInfo info) async {
    try {
      var box = mailClient.selectedMailbox;
      if (box == null || !box.isInbox) {
        final connected =
            await locator<MailService>().connect(mailClient.account);
        if (connected == null) {
          return;
        }
        box = await connected.selectInbox();
      }
      final uidNext = box.uidNext;
      if (uidNext != null) {
        info.updateForClient(mailClient, uidNext);
      }
    } catch (e, s) {
      print(
          'Error while getting Inbox.nextUids for ${mailClient.account.email}: $e $s');
    }
  }

  static Future checkForNewMail() async {
    print('background check at ${DateTime.now()}');
    final prefs = await SharedPreferences.getInstance();

    final prefsValue = prefs.getString(_keyInboxUids);
    if (prefsValue == null) {
      print('WARNING: no previous UID infos found, exiting.');
      return;
    }
    final info = BackgroundUpdateInfo();
    Serializer().deserialize(prefsValue, info);
    final mailService = MailService();
    final accounts = await mailService.loadMailAccounts();
    final notificationService = NotificationService();
    await notificationService.init(checkForLaunchDetails: false);
    // final activeMailNotifications =
    //     await notificationService.getActiveMailNotifications();
    // print('background: got activeMailNotifications=$activeMailNotifications');
    final futures = <Future>[];
    for (final account in accounts) {
      final previousUidNext = info.nextExpectedUidForAccount(account) ?? 0;
      futures.add(
        loadNewMessage(
          mailService,
          account,
          previousUidNext,
          notificationService,
          info,
          // activeMailNotifications
          //     .where((n) => n.accountEmail == accountEmail)
          //     .toList()),
        ),
      );
    }
    await Future.wait(futures);
    if (info.isDirty) {
      final serialized = Serializer().serialize(info);
      await prefs.setString(_keyInboxUids, serialized);
    }
  }

  static Future<void> loadNewMessage(
    MailService mailService,
    MailAccount account,
    int previousUidNext,
    NotificationService notificationService,
    BackgroundUpdateInfo info,
    // List<MailNotificationPayload> activeNotifications,
  ) async {
    try {
      final mailClient = await mailService.connect(account);
      if (mailClient == null) {
        return;
      }
      final inbox = await mailClient.selectInbox();
      final uidNext = inbox.uidNext;
      if (uidNext == previousUidNext || uidNext == null) {
        // print(
        //     'no change for ${account.name}, activeNotifications=$activeNotifications');
        // check outdated notifications that should be removed because the message is deleted or read elsewhere:
        // if (activeNotifications.isNotEmpty) {
        //   final uids = activeNotifications.map((n) => n.uid).toList();
        //   final sequence =
        //       MessageSequence.fromIds(uids as List<int>, isUid: true);
        //   final mimeMessages = await mailClient.fetchMessageSequence(sequence,
        //       fetchPreference: FetchPreference.envelope);
        //   for (final mimeMessage in mimeMessages) {
        //     if (mimeMessage.isSeen) {
        //       notificationService.cancelNotificationForMail(
        //           mimeMessage, mailClient);
        //     }
        //     uids.remove(mimeMessage.uid);
        //   }
        //   // remove notifications for messages that have been deleted:
        //   final email = mailClient.account.email ?? '';
        //   final mailboxName = mailClient.selectedMailbox?.name ?? '';
        //   final mailboxValidity = mailClient.selectedMailbox?.uidValidity ?? 0;
        //   for (final uid in uids) {
        //     final guid = MimeMessage.calculateGuid(
        //       email: email,
        //       mailboxName: mailboxName,
        //       mailboxUidValidity: mailboxValidity,
        //       messageUid: uid,
        //     );
        //     notificationService.cancelNotification(guid);
        //   }
        // }
      } else {
        print(
            'new uidNext=$uidNext, previous=$previousUidNext for ${account.name} uidValidity=${inbox.uidValidity}');
        final sequence = MessageSequence.fromRangeToLast(
          // special care when uidnext of the account was not known before:
          // do not load _all_ messages
          previousUidNext == 0
              ? max(previousUidNext, uidNext - 10)
              : previousUidNext,
          isUidSequence: true,
        );
        info.updateForClient(mailClient, uidNext);
        final mimeMessages = await mailClient.fetchMessageSequence(sequence,
            fetchPreference: FetchPreference.envelope);
        for (final mimeMessage in mimeMessages) {
          if (!mimeMessage.isSeen) {
            notificationService.sendLocalNotificationForMail(
              mimeMessage,
              mailClient,
            );
          }
        }
      }

      await mailClient.disconnect();
    } catch (e, s) {
      print(
          'Unable to process background operation for ${account.name}: $e $s');
    }
  }
}
