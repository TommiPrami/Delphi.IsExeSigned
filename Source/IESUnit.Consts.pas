unit IESUnit.Consts;

interface

const
  EXIT_CODE_NOT_SIGNED = 1;
  EXIT_CODE_PARAM_NOT_FOUND = 2;
  EXIT_CODE_PARAM_VALUE_ERROR = 3;
  EXIT_CODE_EXCEPTION = 4;
  EXIT_CODE_SIGNATURE_NOT_VALID = 5;
  EXIT_CODE_SIGN_COMMAND_NO_FILE_NAME = 6;
  EXIT_CODE_SIGN_TIMEOUT = 7;
  EXIT_CODE_CERTIFICATE_EXPIRING = 8;

  PARAM_CERTIFICATE_EXPIRATION_ERROR = 'CertificateExpirationError';
  PARAM_CERTIFICATE_EXPIRATION_WARNING = 'CertificateExpirationWarning';
  PARAM_FILES = 'Files';
  PARAM_LOG_FILE = 'LogFile';
  PARAM_SIGN_COMMAND = 'SignCommand';
  PARAM_SIGN_FILTER = 'SignFilter';

  SIGN_TIMEOUT_MAX = 86400; // One day
  CERTIFICATE_EXPIRATION_DAYS_MAX = 3650; // Ten years

  SIGN_FILE_NAME_PLACEHOLDER = '%filename%';

  // Width of the name column of the settings Verbose writes: the length of the longest parameter name,
  // CertificateExpirationWarning
  SETTING_NAME_WIDTH = 28;

  // Written to the application folder, when Log is True and LogFile is not given
  LOG_FILE_NAME_DEFAULT = 'IsExeSigned.xml';
  LOG_TEST_SUITE_NAME = 'Signatures';

implementation

end.
