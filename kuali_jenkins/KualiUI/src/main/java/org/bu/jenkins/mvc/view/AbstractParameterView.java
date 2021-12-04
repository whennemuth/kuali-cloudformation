package org.bu.jenkins.mvc.view;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.util.SimpleHttpHandler;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;
import org.thymeleaf.templatemode.TemplateMode;
import org.thymeleaf.templateresolver.ClassLoaderTemplateResolver;

/**
 * An abstract parameter view containing common functionality and fields.
 * Subclasses provide custom view details like template name and location as well as names of relevant template fragments.
 * A default implemetation of the render function is provided that should accommodate most subclasses.
 * 
 * @author wrh
 *
 */
public abstract class AbstractParameterView implements ParameterView {
	
	private Logger logger = LogManager.getLogger(AbstractParameterView.class.getName());

	protected Context context = new Context();
	protected String templateSelector;
	protected String viewName;
	protected boolean asFullWebPage;
	protected boolean readOnly;

	@Override
	public String render() {
		EntryMessage m = logger.traceEntry("render()");
		try {
			TemplateEngine engine = new TemplateEngine();
			ClassLoaderTemplateResolver resolver = new ClassLoaderTemplateResolver();
			resolver.setTemplateMode(TemplateMode.HTML);
			resolver.setCharacterEncoding(StandardCharsets.UTF_8.name());
			resolver.setPrefix(getResolverPrefix());
			resolver.setSuffix(".htm");
			resolver.setCacheable(false);
			resolver.setOrder(1);
			engine.setTemplateResolver(resolver);
			if(templateSelector == null) {
				logger.traceExit(m);
				return engine.process(viewName, context);
			}
			logger.traceExit(m);
			return engine.process(viewName, new HashSet<String>(Arrays.asList(templateSelector)), context);
		} 
		catch (Exception e) {
			logger.traceExit(m, e.getMessage());
			return new ParameterErrorView(e).render();
		}
	}

	@Override
	public boolean isReadOnly() {
		return readOnly;
	}

	public AbstractParameterView setReadOnly(boolean readOnly) {
		this.readOnly = readOnly;
		return this;
	}
	
	public AbstractParameterView setContextVariable(String name, Object obj) {
		context.setVariable(name, obj);
		return this;
	}
	
	public Object getContextVariable(String name) {
		return context.getVariable(name);
	}
	
	public String getTemplateSelector() {
		return templateSelector;
	}

	public AbstractParameterView setTemplateSelector(String templateSelector) {
		this.templateSelector = templateSelector;
		return this;
	}

	public String getViewName() {
		return viewName;
	}

	public AbstractParameterView setViewName(String viewName) {
		this.viewName = viewName;
		return this;
	}

	public boolean isAsFullWebPage() {
		return asFullWebPage;
	}

	public AbstractParameterView setAsFullWebPage(boolean asFullWebPage) {
		this.asFullWebPage = asFullWebPage;
		return this;
	}

	public void willRenderAsFullWebPage(boolean asFullWebPage) {
		this.asFullWebPage = asFullWebPage;
	}

	public static void main(String[] args) {
		AbstractParameterView jsView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return "org/bu/jenkins/active_choices/html/job-javascript/";
			} }
			.setViewName("DynamicBehavior");
			
		String html = jsView.render();
		new SimpleHttpHandler() {
			@Override
			public String getHtml(Map<String, String> parameters) {
				return html;
			}}.visitWithBrowser(false);
		System.out.println(html);
	}

}
