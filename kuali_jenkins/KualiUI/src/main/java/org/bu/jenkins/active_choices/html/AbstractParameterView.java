package org.bu.jenkins.active_choices.html;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Map;

import org.bu.jenkins.SimpleHttpHandler;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;
import org.thymeleaf.templatemode.TemplateMode;
import org.thymeleaf.templateresolver.ClassLoaderTemplateResolver;

/**
 * An abstract parameter view containing common functionality and fields.
 * Subclasses provide custom view details like template name and location as well as names of relevant template fragments.
 * A default implemetation of the render function is provided that should accomodate most subclasses.
 * 
 * @author wrh
 *
 */
public abstract class AbstractParameterView implements ParameterView {

	protected Context context = new Context();
	protected String templateSelector;
	protected String viewName;
	protected boolean asFullWebPage;
	protected boolean readOnly;

	@Override
	public String render() {
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
				return engine.process(viewName, context);
			}
			return engine.process(viewName, new HashSet<String>(Arrays.asList(templateSelector)), context);
		} 
		catch (Exception e) {
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
