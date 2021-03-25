package org.bu.jenkins;

import java.net.URI;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.core.LoggerContext;
import org.apache.logging.log4j.core.appender.ConsoleAppender;
import org.apache.logging.log4j.core.config.Configuration;
import org.apache.logging.log4j.core.config.ConfigurationFactory;
import org.apache.logging.log4j.core.config.ConfigurationSource;
import org.apache.logging.log4j.core.config.builder.api.AppenderComponentBuilder;
import org.apache.logging.log4j.core.config.builder.api.ConfigurationBuilder;
import org.apache.logging.log4j.core.config.builder.api.LayoutComponentBuilder;
import org.apache.logging.log4j.core.config.builder.api.LoggerComponentBuilder;
import org.apache.logging.log4j.core.config.builder.impl.BuiltConfiguration;
import org.apache.logging.log4j.message.EntryMessage;

/**
 * Dynamically create the log4j logging configuration.
 * 
 * @author wrh
 *
 */
public class LoggingConfigFactory extends ConfigurationFactory {
	
	private Level loggingLevel;
	
	public LoggingConfigFactory(Level loggingLevel) {
		this.loggingLevel = loggingLevel;
	}

	@Override
	protected String[] getSupportedTypes() {
		return new String[] {"*"};
	}

	@Override
	public Configuration getConfiguration(LoggerContext loggerContext, ConfigurationSource source) {
		return getConfiguration(loggerContext, source.toString(), null);
	}
	
    @Override
    public Configuration getConfiguration(final LoggerContext loggerContext, final String name, final URI configLocation) {
        ConfigurationBuilder<BuiltConfiguration> builder = newConfigurationBuilder();
        return createConfiguration(name, builder);
    }

	private Configuration createConfiguration(String name, ConfigurationBuilder<BuiltConfiguration> builder) {
		System.out.println(String.format("createConfiguration(name=%s, builder.hashCode()=%s", name, builder.hashCode()));
		builder.setConfigurationName(name);
		// builder.setStatusLevel(Level.WARN);
		builder.add(builder.newRootLogger(Level.WARN));
		
		/** APPENDER */
		AppenderComponentBuilder appenderBuilder = builder.newAppender("Stdout", "CONSOLE").
	            addAttribute("target", ConsoleAppender.Target.SYSTEM_OUT);
		
		/** LAYOUT */
		LayoutComponentBuilder layoutBuilder = builder.newLayout("PatternLayout")
				.addAttribute("pattern", "%d{HH:mm:ss,SSS} %-5p [%t]: %m%n");
		appenderBuilder.add(layoutBuilder);
		
		/** LOGGER */
		LoggerComponentBuilder componentBuilder = builder.newLogger("org.bu.jenkins", loggingLevel)				
			.add(builder.newAppenderRef("Stdout")
			.addAttribute("additivity", false));
		
		return builder
			.add(appenderBuilder)
			.add(componentBuilder)
			.build();
	}


	private void test(String s1, String s2, String s3) {
		Logger logger = LogManager.getLogger(LoggingConfigFactory.class.getName());
		EntryMessage m = logger.traceEntry("test(s1={}, s2={}, s3={})", s1, s2, s3);
		logger.info("hello");
		logger.traceExit(m);
	}

	public static void main(String[] args) {
		System.out.println("Testing...");
		LoggingConfigFactory factory = new LoggingConfigFactory(Level.TRACE);
		ConfigurationFactory.setConfigurationFactory(factory);
		factory.test("one", "two", "three");
	}
}
