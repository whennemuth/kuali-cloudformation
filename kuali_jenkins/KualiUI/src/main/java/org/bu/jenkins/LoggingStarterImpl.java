package org.bu.jenkins;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.core.config.ConfigurationFactory;
import org.apache.logging.log4j.message.EntryMessage;

/**
 * Configure log4j with a custom ConfigurationFactory that sets a logging level indicated by 
 * an environment variable which can be optionally overridden by a named argument.
 * 
 * @author wrh
 *
 */
public class LoggingStarterImpl implements LoggingStarter {
	
	private static final Level DEFAULT_LEVEL = Level.INFO;
	private static final String LOGGING_LEVEL_KEY = "LOGGING_LEVEL";
	
	private Level loggingLevel = DEFAULT_LEVEL;
	
	public LoggingStarterImpl() {
		this(new Environment() {
			@Override public boolean containsKey(String key) {
				return System.getenv().containsKey(key);
			}
			@Override public String get(String key) {
				return System.getenv().get(key);
			}
		});
		System.out.println("LoggingStarterImpl()");
	}
	
	public LoggingStarterImpl(Environment env) {
		super();
		System.out.println(String.format("LoggingStarterImpl(env=%s)", env==null ? "null" : env.hashCode()));
		if(env.containsKey(LOGGING_LEVEL_KEY)) {
			loggingLevel = Level.getLevel(env.get(LOGGING_LEVEL_KEY));
		}
	}

	@Override
	public void start(NamedArgs namedArgs) {
		System.out.println(String.format("LoggingStarterImpl(env=%s)", namedArgs==null ? "null" : namedArgs.hashCode()));
		if(namedArgs != null && namedArgs.has(LOGGING_LEVEL_KEY)) {
			loggingLevel = Level.getLevel(namedArgs.get(LOGGING_LEVEL_KEY));
		}
		ConfigurationFactory.setConfigurationFactory(new LoggingConfigFactory(loggingLevel));
	}
	
	private void test(String s1, String s2, String s3) {
		Logger logger = LogManager.getLogger(LoggingConfigFactory.class.getName());
		EntryMessage m = logger.traceEntry("test(s1={}, s2={}, s3={})", s1, s2, s3);
		logger.info("hello");
		logger.traceExit(m);
	}
	
	public static void main(String[] args) {
		System.out.println("Testing...");

		LoggingStarterImpl starter = new LoggingStarterImpl(new Environment() {
			@Override public boolean containsKey(String key) {				
				return true;
			}
			@Override
			public String get(String key) {
				return Level.TRACE.name();
			}
			
		});
		
		starter.start(null);
		
		starter.test("one", "two", "three");
	}
}
