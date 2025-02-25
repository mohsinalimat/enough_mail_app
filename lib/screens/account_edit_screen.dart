import 'package:collection/collection.dart' show IterableExtension;
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail_app/locator.dart';
import 'package:enough_mail_app/models/account.dart';
import 'package:enough_mail_app/routes.dart';
import 'package:enough_mail_app/screens/all_screens.dart';
import 'package:enough_mail_app/screens/base.dart';
import 'package:enough_mail_app/services/icon_service.dart';
import 'package:enough_mail_app/services/mail_service.dart';
import 'package:enough_mail_app/services/navigation_service.dart';
import 'package:enough_mail_app/services/providers.dart';
import 'package:enough_mail_app/services/scaffold_messenger_service.dart';
import 'package:enough_mail_app/util/localized_dialog_helper.dart';
import 'package:enough_mail_app/util/validator.dart';
import 'package:enough_mail_app/widgets/button_text.dart';
import 'package:enough_mail_app/widgets/password_field.dart';
import 'package:enough_platform_widgets/enough_platform_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AccountEditScreen extends StatefulWidget {
  final Account account;
  const AccountEditScreen({Key? key, required this.account}) : super(key: key);

  @override
  _AccountEditScreenState createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  late TextEditingController _accountNameController;
  late TextEditingController _userNameController;
  bool _isRetryingToConnect = false;

  void _update() {
    setState(() {});
  }

  @override
  void initState() {
    widget.account.addListener(_update);
    _accountNameController = TextEditingController(text: widget.account.name);
    _userNameController = TextEditingController(text: widget.account.userName);
    super.initState();
  }

  @override
  void dispose() {
    widget.account.removeListener(_update);
    _accountNameController.dispose();
    _userNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Base.buildAppChrome(
      context,
      title: localizations.editAccountTitle(widget.account.name),
      subtitle: widget.account.email,
      content: _buildEditContent(localizations, context),
    );
  }

  Widget _buildEditContent(
      AppLocalizations localizations, BuildContext context) {
    final theme = Theme.of(context);
    final iconService = locator<IconService>();
    final mailService = locator<MailService>();
    final account = widget.account;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mailService.hasError(account)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(localizations
                      .editAccountFailureToConnectInfo(account.name)),
                ),
                if (_isRetryingToConnect)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: PlatformProgressIndicator(),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PlatformTextButtonIcon(
                        onPressed: _reconnect,
                        icon: Icon(iconService.retry),
                        label: PlatformText(localizations
                            .editAccountFailureToConnectRetryAction),
                      ),
                      PlatformTextButton(
                        child: PlatformText(localizations
                            .editAccountFailureToConnectChangePasswordAction),
                        onPressed: _updateAuthentication,
                      )
                    ],
                  ),
                Divider(),
              ],
              DecoratedPlatformTextField(
                controller: _accountNameController,
                decoration: InputDecoration(
                  labelText: localizations.addAccountNameOfAccountLabel,
                  hintText: localizations.addAccountNameOfAccountHint,
                ),
                onChanged: (value) async {
                  widget.account.name = value;
                  await locator<MailService>().saveAccounts();
                },
              ),
              DecoratedPlatformTextField(
                controller: _userNameController,
                decoration: InputDecoration(
                  labelText: localizations.addAccountNameOfUserLabel,
                  hintText: localizations.addAccountNameOfUserHint,
                ),
                onChanged: (value) async {
                  widget.account.userName = value;
                  await locator<MailService>().saveAccounts();
                },
              ),
              if (locator<MailService>().hasUnifiedAccount)
                PlatformCheckboxListTile(
                  value: !widget.account.excludeFromUnified,
                  onChanged: (value) async {
                    final exclude = (value == false);
                    widget.account.excludeFromUnified = exclude;
                    setState(() {});
                    await locator<MailService>().excludeAccountFromUnified(
                        widget.account, exclude, context);
                  },
                  title: Text(localizations.editAccountIncludeInUnifiedLabel),
                ),
              Divider(),
              Text(localizations.signatureSettingsTitle,
                  style: theme.textTheme.subtitle1),
              SignatureWidget(
                account: widget.account,
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                child: Text(
                    localizations.editAccountAliasLabel(widget.account.email)),
              ),
              if (widget.account.hasNoAlias)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(localizations.editAccountNoAliasesInfo,
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ),

              for (final alias in widget.account.aliases)
                Dismissible(
                  key: ValueKey(alias),
                  child: PlatformListTile(
                    title: Text(alias.toString()),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => _AliasEditDialog(
                          isNewAlias: false,
                          alias: alias,
                          account: widget.account,
                        ),
                      );
                    },
                  ),
                  background: Container(
                      color: Colors.red,
                      child: Icon(iconService.messageActionDelete)),
                  onDismissed: (direction) async {
                    await widget.account.removeAlias(alias);
                    locator<ScaffoldMessengerService>().showTextSnackBar(
                        localizations.editAccountAliasRemoved(alias.email));
                  },
                ),
              PlatformTextButtonIcon(
                icon: Icon(iconService.add),
                label: Text(localizations.editAccountAddAliasAction),
                onPressed: () {
                  var email = widget.account.email;
                  email = email.substring(email.lastIndexOf('@'));
                  final alias = MailAddress(widget.account.userName, email);
                  showDialog(
                    context: context,
                    builder: (context) => _AliasEditDialog(
                      isNewAlias: true,
                      alias: alias,
                      account: widget.account,
                    ),
                  );
                },
              ),
              // section to test plus alias support
              PlatformCheckboxListTile(
                value: widget.account.supportsPlusAliases,
                onChanged: null,
                title: Text(localizations.editAccountPlusAliasesSupported),
              ),
              PlatformTextButton(
                child:
                    ButtonText(localizations.editAccountCheckPlusAliasAction),
                onPressed: () async {
                  final result = await showPlatformDialog<bool>(
                    context: context,
                    builder: (context) =>
                        _PlusAliasTestingDialog(account: widget.account),
                  );
                  if (result != null) {
                    widget.account.supportsPlusAliases = result;
                    locator<MailService>()
                        .markAccountAsTestedForPlusAlias(widget.account);
                    await locator<MailService>()
                        .saveAccount(widget.account.account);
                  }
                },
              ),

              Row(
                children: [
                  Expanded(
                    child: PlatformCheckboxListTile(
                      value: widget.account.bccMyself,
                      onChanged: (value) async {
                        final bccMyself = (value == true);
                        widget.account.bccMyself = bccMyself;
                        setState(() {});
                        await locator<MailService>()
                            .saveAccount(widget.account.account);
                      },
                      title: Text(localizations.editAccountBccMyself),
                    ),
                  ),
                  PlatformIconButton(
                    icon: Icon(CommonPlatformIcons.info),
                    onPressed: () => LocalizedDialogHelper.showTextDialog(
                      context,
                      localizations.editAccountBccMyselfDescriptionTitle,
                      localizations.editAccountBccMyselfDescriptionText,
                    ),
                  ),
                ],
              ),

              Divider(),
              PlatformTextButtonIcon(
                onPressed: () => locator<NavigationService>().push(
                    Routes.accountServerDetails,
                    arguments: widget.account),
                icon: Icon(Icons.edit),
                label:
                    ButtonText(localizations.editAccountServerSettingsAction),
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: PlatformTextButtonIcon(
                  backgroundColor: Colors.red,
                  style: TextButton.styleFrom(backgroundColor: Colors.red),
                  icon: Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                  label: ButtonText(
                    localizations.editAccountDeleteAccountAction,
                    style: Theme.of(context)
                        .textTheme
                        .button!
                        .copyWith(color: Colors.white),
                  ),
                  onPressed: () async {
                    final result =
                        await LocalizedDialogHelper.askForConfirmation(context,
                            title: localizations
                                .editAccountDeleteAccountConfirmationTitle,
                            query: localizations
                                .editAccountDeleteAccountConfirmationQuery(
                                    _accountNameController.text),
                            action: localizations.actionDelete,
                            isDangerousAction: true);
                    if (result == true) {
                      final mailService = locator<MailService>();
                      await mailService.removeAccount(widget.account, context);
                      if (mailService.accounts.isEmpty) {
                        locator<NavigationService>()
                            .push(Routes.welcome, clear: true);
                      } else {
                        locator<NavigationService>().pop();
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateAuthentication() async {
    final mailService = locator<MailService>();
    final authentication = widget.account.account.incoming?.authentication;
    if (authentication is PlainAuthentication) {
      // simple case: password is directly given,
      // can be edited and account can be updated
      final result = await LocalizedDialogHelper.showWidgetDialog(
          context, _PasswordUpdateDialog(authentication: authentication),
          defaultActions: DialogActions.okAndCancel);
      if (result == true) {
        final outgoingAuth = widget.account.account.outgoing?.authentication;
        if (outgoingAuth is PlainAuthentication) {
          outgoingAuth.password = authentication.password;
        }
        final result = await _reconnect();
        if (result) {
          await mailService.saveAccounts();
        }
      }
    } else if (authentication is OauthAuthentication) {
      // oauth case: restart oauth authentication,
      // save new token
      final provider = locator<ProviderService>()[
          widget.account.account.incoming?.serverConfig?.hostname ?? ''];
      if (provider != null && provider.hasOAuthClient) {
        final token = await provider.oauthClient!
            .authenticate(widget.account.account.email!);
        if (token != null) {
          authentication.token = token;
          final outgoingAuth = widget.account.account.outgoing?.authentication;
          if (outgoingAuth is OauthAuthentication) {
            outgoingAuth.token = token;
          }
          await mailService.saveAccounts();
          _reconnect();
        }
      }
    }
  }

  Future<bool> _reconnect() async {
    setState(() {
      _isRetryingToConnect = true;
    });
    final account = widget.account;
    final mailService = locator<MailService>();
    final result = await mailService.reconnect(account);
    if (mounted) {
      setState(() {
        _isRetryingToConnect = false;
      });
      if (result) {
        final localizations = AppLocalizations.of(context)!;
        LocalizedDialogHelper.showTextDialog(
          context,
          localizations.editAccountFailureToConnectFixedTitle,
          localizations.editAccountFailureToConnectFixedInfo,
        );
      }
    }
    return result;
  }
}

class _PasswordUpdateDialog extends StatefulWidget {
  const _PasswordUpdateDialog({Key? key, required this.authentication})
      : super(key: key);

  final PlainAuthentication authentication;

  @override
  _PasswordUpdateDialogState createState() => _PasswordUpdateDialogState();
}

class _PasswordUpdateDialogState extends State<_PasswordUpdateDialog> {
  late TextEditingController _controller;
  @override
  void initState() {
    _controller = TextEditingController(text: widget.authentication.password);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PasswordField(
      controller: _controller,
      labelText: 'Password',
      onChanged: (text) => widget.authentication.password = text,
    );
  }
}

class _PlusAliasTestingDialog extends StatefulWidget {
  final Account account;
  _PlusAliasTestingDialog({Key? key, required this.account}) : super(key: key);

  @override
  _PlusAliasTestingDialogState createState() => _PlusAliasTestingDialogState();
}

class _PlusAliasTestingDialogState extends State<_PlusAliasTestingDialog> {
  bool _isContinueAvailable = true;
  int _step = 0;
  static const int _maxStep = 1;
  late String _generatedAliasAdddress;
  // MimeMessage? _testMessage;

  @override
  void initState() {
    _generatedAliasAdddress =
        locator<MailService>().generateRandomPlusAlias(widget.account);
    super.initState();
  }

  bool _filter(MailEvent event) {
    if (event is MailLoadEvent) {
      final msg = event.message;
      final to = msg.to;
      if (to != null &&
          to.length == 1 &&
          to.first.email == _generatedAliasAdddress) {
        // this is the test message, plus aliases are supported
        widget.account.supportsPlusAliases = true;
        setState(() {
          _isContinueAvailable = true;
          _step++;
        });
        _deleteMessage(msg);
        return true;
      } else if ((msg.getHeaderValue('auto-submitted') != null) &&
          (msg.isTextPlainMessage()) &&
          (msg.decodeContentText()?.contains(_generatedAliasAdddress) ??
              false)) {
        // this is an automatic reply telling that the address is not available
        setState(() {
          _isContinueAvailable = true;
          _step++;
        });
        _deleteMessage(msg);
        return true;
      }
    }
    return false;
  }

  Future<void> _deleteMessage(MimeMessage msg) async {
    var mailClient = await locator<MailService>().getClientFor(widget.account);
    await mailClient.flagMessage(msg, isDeleted: true);
  }

  @override
  void dispose() async {
    super.dispose();
    var mailClient = await locator<MailService>().getClientFor(widget.account);
    mailClient.removeEventFilter(_filter);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return PlatformAlertDialog(
      title: Text(
          localizations.editAccountTestPlusAliasTitle(widget.account.name)),
      content: SizedBox(
        width: double.maxFinite,
        child: PlatformStepper(
          onStepCancel: _step == 3 ? null : () => Navigator.of(context).pop(),
          onStepContinue: !_isContinueAvailable
              ? null
              : () async {
                  if (_step < _maxStep) {
                    _step++;
                  } else {
                    Navigator.of(context)
                        .pop(widget.account.supportsPlusAliases);
                  }
                  switch (_step) {
                    case 1:
                      setState(() {
                        _isContinueAvailable = false;
                      });
                      // send the email and wait for a response:
                      final msg = MessageBuilder.buildSimpleTextMessage(
                          widget.account.fromAddress,
                          [MailAddress(null, _generatedAliasAdddress)],
                          'This is an automated message testing support for + aliases. Please ignore.',
                          subject: 'Testing + Alias');
                      // _testMessage = msg;
                      final mailClient = await locator<MailService>()
                          .getClientFor(widget.account);
                      mailClient.addEventFilter(_filter);
                      mailClient.sendMessage(msg, appendToSent: false);
                      break;
                  }
                },
          steps: [
            Step(
              title: Text(
                  localizations.editAccountTestPlusAliasStepIntroductionTitle),
              content: Text(
                localizations.editAccountTestPlusAliasStepIntroductionText(
                    widget.account.name, _generatedAliasAdddress),
                style: TextStyle(fontSize: 12),
              ),
              isActive: (_step == 0),
            ),
            Step(
              title:
                  Text(localizations.editAccountTestPlusAliasStepTestingTitle),
              content: Center(child: PlatformProgressIndicator()),
              isActive: (_step == 1),
            ),
            Step(
              title:
                  Text(localizations.editAccountTestPlusAliasStepResultTitle),
              content: widget.account.supportsPlusAliases
                  ? Text(
                      localizations.editAccountTestPlusAliasStepResultSuccess(
                          widget.account.name))
                  : Text(
                      localizations.editAccountTestPlusAliasStepResultNoSuccess(
                          widget.account.name)),
              isActive: (_step == 3),
              state: StepState.complete,
            ),
          ],
          currentStep: _step,
        ),
      ),
    );
  }
}

class _AliasEditDialog extends StatefulWidget {
  final MailAddress alias;
  final Account account;
  final bool isNewAlias;
  _AliasEditDialog({
    Key? key,
    required this.isNewAlias,
    required this.alias,
    required this.account,
  }) : super(key: key);

  @override
  _AliasEditDialogState createState() => _AliasEditDialogState();
}

class _AliasEditDialogState extends State<_AliasEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late bool _isEmailValid;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    _nameController = TextEditingController(text: widget.alias.personalName);
    _emailController = TextEditingController(text: widget.alias.email);
    _isEmailValid = !widget.isNewAlias;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return PlatformAlertDialog(
      title: Text(widget.isNewAlias
          ? localizations.editAccountAddAliasTitle
          : localizations.editAccountEditAliasTitle),
      content: _isSaving
          ? PlatformProgressIndicator()
          : _buildContent(localizations),
      actions: [
        PlatformTextButton(
          child: ButtonText(localizations.actionCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        PlatformTextButton(
          child: ButtonText(widget.isNewAlias
              ? localizations.editAccountAliasAddAction
              : localizations.editAccountAliasUpdateAction),
          onPressed: _isEmailValid
              ? () async {
                  setState(() {
                    _isSaving = true;
                  });
                  widget.alias.email = _emailController.text;
                  widget.alias.personalName = _nameController.text;
                  await widget.account.addAlias(widget.alias);
                  Navigator.of(context).pop();
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildContent(AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedPlatformTextField(
          controller: _nameController,
          decoration: InputDecoration(
              labelText: localizations.editAccountEditAliasNameLabel,
              hintText: localizations.addAccountNameOfUserHint),
        ),
        DecoratedPlatformTextField(
          controller: _emailController,
          decoration: InputDecoration(
              labelText: localizations.editAccountEditAliasEmailLabel,
              hintText: localizations.editAccountEditAliasEmailHint),
          onChanged: (value) {
            bool isValid = Validator.validateEmail(value);
            final emailValue = value.toLowerCase();
            if (isValid) {
              final existingAlias = widget.account.aliases
                  .firstWhereOrNull((e) => e.email.toLowerCase() == emailValue);
              if (existingAlias != null && existingAlias != widget.alias) {
                setState(() {
                  _errorMessage =
                      localizations.editAccountEditAliasDuplicateError(value);
                });
              } else if (_errorMessage != null) {
                setState(() {
                  _errorMessage = null;
                });
              }
            }
            if (isValid != _isEmailValid) {
              setState(() {
                _isEmailValid = isValid;
              });
            }
          },
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}
