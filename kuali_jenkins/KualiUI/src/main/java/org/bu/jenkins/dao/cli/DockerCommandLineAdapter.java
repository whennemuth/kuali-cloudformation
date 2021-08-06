package org.bu.jenkins.dao.cli;

import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.dao.AbstractDockerDAO;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.StringToList;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * Docker utility class that acts as a Adapter for direct command line use of docker.
 * 
 * @author wrh
 *
 */
public class DockerCommandLineAdapter extends AbstractDockerDAO {
	
	Logger logger = LogManager.getLogger(DockerCommandLineAdapter.class.getName());

	private RuntimeCommand cmd;
	
	public DockerCommandLineAdapter(RuntimeCommand cmd) {
		super();
		this.cmd = cmd;
	}
	
	/**
	 * Get the readout of the docker images command as a string
	 * @return
	 */
	private String printImages() {
		cmd.setArgs("docker", "images", "--format", "{{.Repository}}:{{.Tag}}");
		if(cmd.run()) {
			if(cmd.hasError()) {
				return cmd.getErrorOutput();
			}
			else {
				return cmd.getOutput();
			}
		}
		else {
			logger.error("Could not get docker images!");
			return "";
		}
	}
	
	/**
	 * Parse the readout of the docker images command into a list of all docker images in the private 
	 * repository, only including tags if they are explicit and not a default.
	 * @return
	 */
	@Override
	public List<String> getImages() {		
		return new StringToList(printImages()) {
			@Override public String filter(String image) {
				if(image.contains(":")) {
					String tag = image.split(":")[1];
					if(tag.isBlank()  || "latest".equalsIgnoreCase(tag)  || "<none>".equalsIgnoreCase(tag)) {
						return image.split(":")[0];
					}
				}
				return image;
			}
			
		}.getList();
	}
	
	public static void main(String[] args) {
		@SuppressWarnings("unused")
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		AbstractDockerDAO dao = new DockerCommandLineAdapter(RuntimeCommand.getCommandInstance());
		for(String image : dao.getImages()) {
			System.out.println(image);
		}
	}

}
