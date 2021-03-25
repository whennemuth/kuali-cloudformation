package org.bu.jenkins.job;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Constructor;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.CaseInsensitiveEnvironment;
import org.bu.jenkins.LoggingStarterImpl;
import org.bu.jenkins.NamedArgs;
import org.bu.jenkins.SimpleHttpHandler;
import org.bu.jenkins.active_choices.html.AbstractParameterView;

/**
 * This class provides for subclasses basic functionality for outputting the combined html associated with all
 * active choices driven fields of any given jenkins job. Subclasses must provide the implementation for the
 * html generation at the individual field level.
 *  
 * @author wrh
 *
 */
public abstract class AbstractJob {
	
	private Logger logger = LogManager.getLogger(AbstractJob.class.getName());

	protected AWSCredentials credentials = AWSCredentials.getInstance();
	protected String ajaxHost;

	public AbstractJob() {
		super();
	}

	public abstract String getRenderedParameter(JobParameterConfiguration configuration);
	
	public abstract String getJobName();
	
	public abstract JobParameterMetadata[] getJobParameterMetadata();
	
	public abstract void checkJobParameterConfig(JobParameterConfiguration config);
	
	public String getAjaxHost() {
		return ajaxHost;
	}

	public void setAjaxHost(String ajaxHost) {
		this.ajaxHost = ajaxHost;
	}

	public JobParameterMetadata getParameterMetadata(String parmName) {
		for(JobParameterMetadata meta: getJobParameterMetadata()) {
			if(meta.toString().equalsIgnoreCase(parmName)) {
				return meta;
			}
		}
		return null;
	}
	
	/**
	 * In a jenkins job, the active choices parameters will be rendered individually. However, to get a view of what the 
	 * entire jenkins job will look like, this function will combine all parameter renderings in the job and display them in a
	 * browser as a sort of test harness.
	 * @param parameters
	 * @return
	 */
	public String getRenderedJob(Map<String, String> parameters, boolean developmentMode) {
		EntryMessage m = logger.traceEntry(
				"getRenderedJob(parameters.size()={}, developmentMode={})", 
				parameters==null ? "null" : parameters.size(), 
				developmentMode);
		StringBuilder html = new StringBuilder();
		try {
			html.append(getCssView())
				.append("<form method='GET' name='kuali-parameters' id='kuali-parameters'>")
				.append("<div id='kuali-wrapper'>")
				.append("<fieldset id='all-fields'>")
				.append("<input type='hidden' id='" + getJobName() + "'>");
			// Add the html of each parameter to the output one by one.
			for (JobParameterMetadata fieldMeta : getJobParameterMetadata()) {
				String parmName = fieldMeta.toString();
				JobParameterConfiguration config = JobParameterConfiguration.forTestFragmentInstance(parmName);
				config.setParameterMap(parameters);
				checkJobParameterConfig(config);
				html.append(getRenderedParameter(config));
			}
			html
				.append("</fieldset>")
				.append("</div>")
				.append("</form>");

			if(developmentMode) {
				/**
				 * NOTE: For some unknown reason, including the javascript with all of the parameter html will not work on a
				 * jenkins server (not developmentMode), even with the CORS disabled. The script gets blocked somehow, letting
				 * the html and css through but not showing in the debug window. So, the workaround for this is for a separate
				 * active choices reactive parameter to make it's own http request to acquire the javascript alone (add a 
				 * "?scripts-only=true" querystring parameter to the url). This seems to work.
				 */
				html.append(getJavascriptView(developmentMode));
				html.insert(0, "<html><body>");
				html.append("</body></html>");
			}
			logger.traceExit(m, html.length());
			return html.toString();
		} 
		catch (Exception e) {
			e.printStackTrace(System.out);
			logger.traceExit(m, e.getMessage());
			return stackTraceToHTML(e);
		}
	}
	
	protected String getJavascriptView(boolean developmentMode) {
		EntryMessage m = logger.traceEntry("getJavascriptView(developmentMode={})", developmentMode);
		AbstractParameterView javascriptView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return "org/bu/jenkins/active_choices/html/job-javascript/";
			} }
			.setViewName("DynamicBehavior")
			.setTemplateSelector("dynamic-behavior")
			.setContextVariable("jobName", getJobName())
			.setContextVariable("mode", developmentMode ? "development" : "UnoChoice")
			.setContextVariable("ajaxHost", ajaxHost);
		String retval = javascriptView.render();
		logger.traceExit(m, retval==null ? "null" : retval.length());
		return retval;
	}
	
	protected String getCssView() {
		EntryMessage m = logger.traceEntry("getCssView()");
		AbstractParameterView cssView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return "org/bu/jenkins/active_choices/html/job-css/";
			} }
			.setViewName("Stylesheet")
			.setTemplateSelector("stack-stylesheet");
		String retval = cssView.render();
		logger.traceExit(m, retval==null ? "null" : retval.length());
		return retval;
	}
	
	/**
	 * Get a parameterView with the "boilerplate" fields set.
	 * @param config
	 * @return
	 */
	protected AbstractParameterView getSparseParameterView(JobParameterConfiguration config, String resolverPrefix) throws Exception {
		EntryMessage m = logger.traceEntry(
				"getSparseParameterView(config.getParameterName()={}, resolverPrefix={})", 
				config==null ? "null" : config.getParameterName(), 
				resolverPrefix);
		JobParameterMetadata parameter = getParameterMetadata(config.getParameterName());
		AbstractParameterView parameterView = new AbstractParameterView() {
			@Override public String getResolverPrefix() {
				return resolverPrefix;
			} 
		}
		.setViewName(parameter.getViewName())
		.setTemplateSelector(parameter.getTemplateSelector())
		.setAsFullWebPage( ! config.isFragment());
			
		if(config.getParameterMap().containsKey(parameter.toString())) {
			String value = config.getParameterMap().get(parameter.toString());
			parameterView.setContextVariable("ParameterValue", value);
		}
		if( ! config.isActiveChoices()) {
			parameterView.setContextVariable("ParameterName", parameter.toString());
		}
		logger.traceExit(m, parameterView.getViewName());
		return parameterView;
	}

	public static String stackTraceToHTML(Exception e) {
        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);
        if(e.getMessage() != null) {
          pw.write(e.getMessage());
        }
        pw.write("\n");
        e.printStackTrace(pw);
        return "<pre>" + sw.toString() + "</pre>";
	}
	
	public static void main(String[] args) throws Exception {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		if(namedArgs.has("job-class")) {
			Class<?> jobclass = Class.forName(namedArgs.get("job-class"));
			Constructor<?> constructor = jobclass.getConstructor(AWSCredentials.class);
			AbstractJob job = (AbstractJob) constructor.newInstance(AWSCredentials.getInstance(namedArgs));
			job.setAjaxHost(namedArgs.get("ajax-host", "127.0.0.1"));
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					try {
						if(parameters.containsKey("scripts-only")) {
							return job.getJavascriptView(namedArgs.getBoolean("developmentMode"));
						}
						else {
							return job.getRenderedJob(parameters, namedArgs.getBoolean("developmentMode"));
						}
					} 
					catch (Exception e) {
						e.printStackTrace(System.out);
						return stackTraceToHTML(e);
					}
				}}.start();
			System.out.println(namedArgs.get("job-class") + " job server started.");	
		}
		else {
			System.out.println("Required \"job-class\" argument!");
		}
	}
}