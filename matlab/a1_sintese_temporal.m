function a1_sintese_temporal(raizRepositorio)
%A1_SINTESE_TEMPORAL Consolida as principais evidencias temporais do projeto.

if nargin < 1 || strlength(string(raizRepositorio)) == 0
    diretorioScript = fileparts(mfilename('fullpath'));
    raizRepositorio = fileparts(diretorioScript);
end
raizRepositorio = string(raizRepositorio);
assert(isfolder(fullfile(raizRepositorio, 'resultados')), ...
    'Repositorio invalido: %s', raizRepositorio);

dirResultados = fullfile(raizRepositorio, 'resultados');
dirFiguras = fullfile(dirResultados, 'figuras');
if ~isfolder(dirFiguras)
    mkdir(dirFiguras);
end

arquivoE3 = fullfile(dirResultados, 'traces', 'e3', ...
    'E3_TRACE.csv');
arquivoE5b = fullfile(dirResultados, 'metricas', 'e5b', ...
    'E5B_FASES.csv');
arquivoE8 = fullfile(dirResultados, 'metricas', 'e8', ...
    'E8_METRICAS.csv');
arquivoE9 = fullfile(dirResultados, 'metricas', 'e9', ...
    'E9_METRICAS.csv');
arquivoE10 = fullfile(dirResultados, 'metricas', 'e10', ...
    'E10_METRICAS.csv');

traceE3 = lerCsv(arquivoE3);
fasesE5b = lerCsv(arquivoE5b);
metricasE8 = lerCsv(arquivoE8);
metricasE9 = lerCsv(arquivoE9);
metricasE10 = lerCsv(arquivoE10);

validarFontes(traceE3, fasesE5b, metricasE8, metricasE9, metricasE10);
gerarDiagramaTemporal(traceE3, fullfile(dirFiguras, ...
    'A1_DIAGRAMA_TEMPORAL_E3.png'));
gerarPainel(fasesE5b, metricasE8, metricasE9, metricasE10, ...
    fullfile(dirFiguras, 'A1_PAINEL_EVIDENCIAS.png'));

fprintf('A1 concluida.\n');
fprintf('Diagrama: %s\n', fullfile(dirFiguras, ...
    'A1_DIAGRAMA_TEMPORAL_E3.png'));
fprintf('Painel:   %s\n', fullfile(dirFiguras, ...
    'A1_PAINEL_EVIDENCIAS.png'));
end

function tabela = lerCsv(arquivo)
assert(isfile(arquivo), 'Fonte ausente: %s', arquivo);
opcoes = detectImportOptions(arquivo, 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
tabela = readtable(arquivo, opcoes);
end

function validarFontes(traceE3, fasesE5b, metricasE8, metricasE9, metricasE10)
assert(height(fasesE5b) == 10 && height(metricasE8) == 5 && ...
    height(metricasE9) == 8 && height(metricasE10) == 3, ...
    'Quantidade inesperada de registros nas fontes da A1.');
assert(all(fasesE5b.jobs_aquisicao == 21), ...
    'E5b nao contem 21 aquisicoes por fase.');
assert(all(metricasE8.repeticoes == 5) && ...
    all(metricasE10.repeticoes == 30), ...
    'Repeticoes incompletas em E8 ou E10.');

tarefas = string(traceE3.tarefa);
for nome = ["AQUISICAO", "CONTROLE", "ATUACAO"]
    assert(sum(tarefas == nome & traceE3.sequencia == 0) == 1, ...
        'Trace E3 sem registro unico de %s na sequencia 0.', nome);
end
end

function gerarDiagramaTemporal(trace, arquivo)
tarefas = ["AQUISICAO", "CONTROLE", "ATUACAO"];
rotulos = ["Aquisição", "Controle", "Atuação"];
cores = [0.1216 0.4667 0.7059; 0.9294 0.4902 0.1922; ...
    0.4667 0.6745 0.1882];
inicio = zeros(3,1);
fim = zeros(3,1);
duracao = zeros(3,1);

nomesTrace = string(trace.tarefa);
registroAquisicao = trace(nomesTrace == "AQUISICAO" & ...
    trace.sequencia == 0, :);
origemUs = registroAquisicao.liberacao_us;
for k = 1:3
    r = trace(nomesTrace == tarefas(k) & trace.sequencia == 0, :);
    inicio(k) = (r.inicio_us - origemUs)/1000;
    fim(k) = (r.termino_us - origemUs)/1000;
    duracao(k) = r.execucao_us/1000;
end

fig = figure('Color', 'w', 'Visible', 'off', ...
    'Position', [100 100 1500 820], 'Name', 'A1 - diagrama temporal E3');
layout = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax1 = nexttile(layout);
desenharBarras(ax1, inicio, fim, rotulos, cores);
xline(ax1, 600, '--r', 'Deadline da aquisição: 600 ms', ...
    'LabelHorizontalAlignment', 'right', 'LineWidth', 1.2);
xlim(ax1, [0 650]);
xlabel(ax1, 'Tempo desde a liberação da aquisição (ms)');
title(ax1, 'Caminho crítico completo — E3 nominal, sequência 0');
text(ax1, mean([inicio(1) fim(1)]), 1, ...
    sprintf('%.3f ms', duracao(1)), 'HorizontalAlignment', 'center', ...
    'Color', 'w', 'FontWeight', 'bold');

ax2 = nexttile(layout);
desenharBarras(ax2, inicio, fim, rotulos, cores);
margem = 0.20;
xlim(ax2, [fim(1)-0.25 fim(3)+margem]);
xlabel(ax2, 'Tempo desde a liberação da aquisição (ms)');
title(ax2, 'Ampliação do final da aquisição, controle e atuação');
for k = 2:3
    text(ax2, mean([inicio(k) fim(k)]), k, ...
        sprintf('%.0f us', duracao(k)*1000), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

sgtitle(layout, sprintf(['A1 — precedência real aquisição → controle → atuação ' ...
    '(resposta fim a fim: %.3f ms; deadline: 5,715 s)'], fim(3)));
exportgraphics(fig, arquivo, 'Resolution', 200);
close(fig);
end

function desenharBarras(ax, inicio, fim, rotulos, cores)
hold(ax, 'on');
for k = 1:numel(inicio)
    y = [k-0.28 k-0.28 k+0.28 k+0.28];
    x = [inicio(k) fim(k) fim(k) inicio(k)];
    patch(ax, x, y, cores(k,:), 'EdgeColor', cores(k,:)*0.65, ...
        'LineWidth', 1.0);
end
grid(ax, 'on');
yticks(ax, 1:3);
yticklabels(ax, rotulos);
ylim(ax, [0.5 3.5]);
ax.YDir = 'reverse';
ax.FontSize = 11;
end

function gerarPainel(e5b, e8, e9, e10, arquivo)
fig = figure('Color', 'w', 'Visible', 'off', ...
    'Position', [100 100 1700 1050], 'Name', 'A1 - painel de evidencias');
layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax1 = nexttile(layout);
baixa = e5b(e5b.prioridade == 1, :);
alta = e5b(e5b.prioridade == 5, :);
plot(ax1, baixa.carga_pct, baixa.resposta_aquisicao_max_us/1000, ...
    '-o', 'LineWidth', 1.8, 'MarkerFaceColor', [0.1216 0.4667 0.7059]);
hold(ax1, 'on');
plot(ax1, alta.carga_pct, alta.resposta_aquisicao_max_us/1000, ...
    '-s', 'LineWidth', 1.8, 'MarkerFaceColor', [0.8500 0.3250 0.0980]);
yline(ax1, 600, '--r', 'Deadline: 600 ms', 'LineWidth', 1.2);
text(ax1, 60, alta.resposta_aquisicao_max_us(end)/1000 + 9, ...
    '3 perdas', 'HorizontalAlignment', 'right', 'Color', [0.75 0 0]);
grid(ax1, 'on');
xlabel(ax1, 'Carga nominal (%)');
ylabel(ax1, 'Resposta máxima da aquisição (ms)');
title(ax1, 'E5b — efeito da prioridade');
legend(ax1, {'Prioridade 1', 'Prioridade 5'}, 'Location', 'northwest');

ax2 = nexttile(layout);
usoDeadline = 100*e8.latencia_max_us./e8.deadline_us;
bar(ax2, usoDeadline, 'FaceColor', [0.4667 0.6745 0.1882]);
grid(ax2, 'on');
ylabel(ax2, 'Maior latência / deadline (%)');
title(ax2, 'E8 — margem dos caminhos seguros');
xticks(ax2, 1:5);
xticklabels(ax2, {'STOP', 'Sensor', 'Temperatura', 'Heartbeat', 'BOOT'});
xtickangle(ax2, 18);
for k = 1:height(e8)
    text(ax2, k, usoDeadline(k)+0.7, sprintf('%.2f%%', usoDeadline(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9);
end
ylim(ax2, [0 max(30, max(usoDeadline)*1.22)]);

ax3 = nexttile(layout);
nomesE9 = string(e9.operacao);
selecionadas = ["ESP_TIMER_PAIR", "TRACE_PIPELINE", "SNPRINTF_TRACE"];
custosUs = zeros(3,1);
for k = 1:3
    custosUs(k) = e9.media_ns(nomesE9 == selecionadas(k))/1000;
end
bar(ax3, custosUs, 'FaceColor', [0.4940 0.1840 0.5560]);
grid(ax3, 'on');
ylabel(ax3, 'Custo médio (us)');
title(ax3, 'E9 — custo da instrumentação');
xticks(ax3, 1:3);
xticklabels(ax3, {'Par de timestamps', 'Pipeline binário', 'Formatação textual'});
xtickangle(ax3, 18);
for k = 1:3
    text(ax3, k, custosUs(k)+1.0, sprintf('%.3f us', custosUs(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9);
end
ylim(ax3, [0 max(custosUs)*1.18]);

ax4 = nexttile(layout);
bar(ax4, e10.espera_mediana_us/1000, ...
    'FaceColor', [0.9294 0.6941 0.1255]);
grid(ax4, 'on');
ylabel(ax4, 'Espera mediana da tarefa alta (ms)');
title(ax4, 'E10 — herança de prioridade');
xticks(ax4, 1:3);
xticklabels(ax4, {'Mutex baseline', 'Mutex com herança', 'Semáforo binário'});
xtickangle(ax4, 18);
for k = 1:height(e10)
    text(ax4, k, e10.espera_mediana_us(k)/1000 + 1.0, ...
        sprintf('%.3f ms | P_{baixa}=%d', ...
        e10.espera_mediana_us(k)/1000, ...
        e10.prioridade_efetiva_baixa(k)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9);
end
ylim(ax4, [0 max(e10.espera_mediana_us/1000)*1.18]);

sgtitle(layout, 'A1 — síntese das evidências temporais e de concorrência');
exportgraphics(fig, arquivo, 'Resolution', 200);
close(fig);
end
