var obj = {
  Id: 'STRING_VALUE', /* required */
  LockToken: 'STRING_VALUE', /* required */
  Name: 'STRING_VALUE', /* required */
  Scope: CLOUDFRONT | REGIONAL, /* required */
  VisibilityConfig: { /* required */
    CloudWatchMetricsEnabled: true || false, /* required */
    MetricName: 'STRING_VALUE', /* required */
    SampledRequestsEnabled: true || false /* required */
  },
  Description: 'STRING_VALUE',
  Rules: [
    {
      Name: 'STRING_VALUE', /* required */
      Priority: 'NUMBER_VALUE', /* required */
      Statement: { /* Statement */ /* required */
        AndStatement: {
          Statements: [ /* required */
            /* recursive Statement */,
            /* more items */
          ]
        },
        ByteMatchStatement: {
          FieldToMatch: { /* required */
            AllQueryArguments: {
            },
            Body: {
            },
            Method: {
            },
            QueryString: {
            },
            SingleHeader: {
              Name: 'STRING_VALUE' /* required */
            },
            SingleQueryArgument: {
              Name: 'STRING_VALUE' /* required */
            },
            UriPath: {
            }
          },
          PositionalConstraint: EXACTLY | STARTS_WITH | ENDS_WITH | CONTAINS | CONTAINS_WORD, /* required */
          SearchString: Buffer.from('...') || 'STRING_VALUE' /* Strings will be Base-64 encoded on your behalf */, /* required */
          TextTransformations: [ /* required */
            {
              Priority: 'NUMBER_VALUE', /* required */
              Type: NONE | COMPRESS_WHITE_SPACE | HTML_ENTITY_DECODE | LOWERCASE | CMD_LINE | URL_DECODE /* required */
            },
            /* more items */
          ]
        },
        GeoMatchStatement: {
          CountryCodes: [
            AF | AX | AL | DZ | AS | AD | AO | AI | AQ | AG | AR | AM | AW | AU | AT | AZ | BS | BH | BD | BB | BY | BE | BZ | BJ | BM | BT | BO | BQ | BA | BW | BV | BR | IO | BN | BG | BF | BI | KH | CM | CA | CV | KY | CF | TD | CL | CN | CX | CC | CO | KM | CG | CD | CK | CR | CI | HR | CU | CW | CY | CZ | DK | DJ | DM | DO | EC | EG | SV | GQ | ER | EE | ET | FK | FO | FJ | FI | FR | GF | PF | TF | GA | GM | GE | DE | GH | GI | GR | GL | GD | GP | GU | GT | GG | GN | GW | GY | HT | HM | VA | HN | HK | HU | IS | IN | ID | IR | IQ | IE | IM | IL | IT | JM | JP | JE | JO | KZ | KE | KI | KP | KR | KW | KG | LA | LV | LB | LS | LR | LY | LI | LT | LU | MO | MK | MG | MW | MY | MV | ML | MT | MH | MQ | MR | MU | YT | MX | FM | MD | MC | MN | ME | MS | MA | MZ | MM | NA | NR | NP | NL | NC | NZ | NI | NE | NG | NU | NF | MP | NO | OM | PK | PW | PS | PA | PG | PY | PE | PH | PN | PL | PT | PR | QA | RE | RO | RU | RW | BL | SH | KN | LC | MF | PM | VC | WS | SM | ST | SA | SN | RS | SC | SL | SG | SX | SK | SI | SB | SO | ZA | GS | SS | ES | LK | SD | SR | SJ | SZ | SE | CH | SY | TW | TJ | TZ | TH | TL | TG | TK | TO | TT | TN | TR | TM | TC | TV | UG | UA | AE | GB | US | UM | UY | UZ | VU | VE | VN | VG | VI | WF | EH | YE | ZM | ZW,
            /* more items */
          ],
          ForwardedIPConfig: {
            FallbackBehavior: MATCH | NO_MATCH, /* required */
            HeaderName: 'STRING_VALUE' /* required */
          }
        },
        IPSetReferenceStatement: {
          ARN: 'STRING_VALUE', /* required */
          IPSetForwardedIPConfig: {
            FallbackBehavior: MATCH | NO_MATCH, /* required */
            HeaderName: 'STRING_VALUE', /* required */
            Position: FIRST | LAST | ANY /* required */
          }
        },
        ManagedRuleGroupStatement: {
          Name: 'STRING_VALUE', /* required */
          VendorName: 'STRING_VALUE', /* required */
          ExcludedRules: [
            {
              Name: 'STRING_VALUE' /* required */
            },
            /* more items */
          ]
        },
        NotStatement: {
          Statement: /* recursive Statement */
        },
        OrStatement: {
          Statements: [ /* required */
            /* recursive Statement */,
            /* more items */
          ]
        },
        RateBasedStatement: {
          AggregateKeyType: IP | FORWARDED_IP, /* required */
          Limit: 'NUMBER_VALUE', /* required */
          ForwardedIPConfig: {
            FallbackBehavior: MATCH | NO_MATCH, /* required */
            HeaderName: 'STRING_VALUE' /* required */
          },
          ScopeDownStatement: /* recursive Statement */
        },
        RegexPatternSetReferenceStatement: {
          ARN: 'STRING_VALUE', /* required */
          FieldToMatch: { /* required */
            AllQueryArguments: {
            },
            Body: {
            },
            Method: {
            },
            QueryString: {
            },
            SingleHeader: {
              Name: 'STRING_VALUE' /* required */
            },
            SingleQueryArgument: {
              Name: 'STRING_VALUE' /* required */
            },
            UriPath: {
            }
          },
          TextTransformations: [ /* required */
            {
              Priority: 'NUMBER_VALUE', /* required */
              Type: NONE | COMPRESS_WHITE_SPACE | HTML_ENTITY_DECODE | LOWERCASE | CMD_LINE | URL_DECODE /* required */
            },
            /* more items */
          ]
        },
        RuleGroupReferenceStatement: {
          ARN: 'STRING_VALUE', /* required */
          ExcludedRules: [
            {
              Name: 'STRING_VALUE' /* required */
            },
            /* more items */
          ]
        },
        SizeConstraintStatement: {
          ComparisonOperator: EQ | NE | LE | LT | GE | GT, /* required */
          FieldToMatch: { /* required */
            AllQueryArguments: {
            },
            Body: {
            },
            Method: {
            },
            QueryString: {
            },
            SingleHeader: {
              Name: 'STRING_VALUE' /* required */
            },
            SingleQueryArgument: {
              Name: 'STRING_VALUE' /* required */
            },
            UriPath: {
            }
          },
          Size: 'NUMBER_VALUE', /* required */
          TextTransformations: [ /* required */
            {
              Priority: 'NUMBER_VALUE', /* required */
              Type: NONE | COMPRESS_WHITE_SPACE | HTML_ENTITY_DECODE | LOWERCASE | CMD_LINE | URL_DECODE /* required */
            },
            /* more items */
          ]
        },
        SqliMatchStatement: {
          FieldToMatch: { /* required */
            AllQueryArguments: {
            },
            Body: {
            },
            Method: {
            },
            QueryString: {
            },
            SingleHeader: {
              Name: 'STRING_VALUE' /* required */
            },
            SingleQueryArgument: {
              Name: 'STRING_VALUE' /* required */
            },
            UriPath: {
            }
          },
          TextTransformations: [ /* required */
            {
              Priority: 'NUMBER_VALUE', /* required */
              Type: NONE | COMPRESS_WHITE_SPACE | HTML_ENTITY_DECODE | LOWERCASE | CMD_LINE | URL_DECODE /* required */
            },
            /* more items */
          ]
        },
        XssMatchStatement: {
          FieldToMatch: { /* required */
            AllQueryArguments: {
            },
            Body: {
            },
            Method: {
            },
            QueryString: {
            },
            SingleHeader: {
              Name: 'STRING_VALUE' /* required */
            },
            SingleQueryArgument: {
              Name: 'STRING_VALUE' /* required */
            },
            UriPath: {
            }
          },
          TextTransformations: [ /* required */
            {
              Priority: 'NUMBER_VALUE', /* required */
              Type: NONE | COMPRESS_WHITE_SPACE | HTML_ENTITY_DECODE | LOWERCASE | CMD_LINE | URL_DECODE /* required */
            },
            /* more items */
          ]
        }
      },
      VisibilityConfig: { /* required */
        CloudWatchMetricsEnabled: true || false, /* required */
        MetricName: 'STRING_VALUE', /* required */
        SampledRequestsEnabled: true || false /* required */
      },
      Action: {
        Allow: {
        },
        Block: {
        },
        Count: {
        }
      },
      OverrideAction: {
        Count: {
        },
        None: {
        }
      }
    },
    /* more items */
  ]
}